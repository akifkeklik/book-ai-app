import json
import logging
from datetime import datetime, timezone
from flask import request, has_request_context, g
import traceback
import re

class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_record = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
        }

        if has_request_context():
            log_record["request_id"] = getattr(g, "request_id", None)
            log_record["endpoint"] = request.endpoint
            log_record["method"] = request.method
            if getattr(g, "user_id", None):
                log_record["user_id"] = g.user_id
            
        if record.exc_info:
            log_record["error_type"] = record.exc_info[0].__name__
            # Only include traceback in debug mode or if explicitly requested, to avoid leaking secrets
            # But usually we log tracebacks safely if we redact. 
            # We will just log the error type and a safe string.
            log_record["error_details"] = str(record.exc_info[1])

        # Add any extra arguments passed via extra={...}
        if hasattr(record, "extra_data"):
            log_record.update(record.extra_data)

        # Redact sensitive fields if any sneaked in
        log_record = self._redact(log_record)

        return json.dumps(log_record)

    def _redact(self, data):
        sensitive_keys = {"api_key", "token", "password", "authorization", "secret", "prompt"}
        if isinstance(data, dict):
            new_dict = {}
            for key, value in data.items():
                if any(s in key.lower() for s in sensitive_keys):
                    new_dict[key] = "***REDACTED***"
                else:
                    new_dict[key] = self._redact(value)
            return new_dict
        elif isinstance(data, list):
            return [self._redact(item) for item in data]
        elif isinstance(data, str):
            # Regex to catch "token=XYZ", "api_key: ABC", etc.
            return re.sub(
                r'(?i)(api_key|token|password|authorization|secret)[\s:=]+([^\s,;\"\'\}]+)',
                r'\1=***REDACTED***',
                data
            )
        return data

def setup_logger():
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)
    
    # Remove existing handlers
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)
        
    handler = logging.StreamHandler()
    handler.setFormatter(JSONFormatter())
    logger.addHandler(handler)
    
    # Silence chatty loggers
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("werkzeug").setLevel(logging.WARNING)

def log_event(name, level=logging.INFO, **kwargs):
    logger = logging.getLogger(name)
    msg = kwargs.pop("msg", "Event occurred")
    exc_info = kwargs.pop("exc_info", None)
    logger.log(level, msg, exc_info=exc_info, extra={"extra_data": kwargs})
