import os
import sys

sys.path.append(os.path.abspath(os.path.dirname(os.path.dirname(__file__))))

import yaml

from app import create_app

app = create_app()
app.testing = True
client = app.test_client()

# Check /api/docs
resp = client.get('/api/docs')
print("/api/docs HTTP Status:", resp.status_code)
if resp.status_code == 200:
    print("Contains swagger-ui:", b"swagger-ui" in resp.data)

# Check /api/docs/openapi.yaml
resp_yaml = client.get('/api/docs/openapi.yaml')
print("/api/docs/openapi.yaml HTTP Status:", resp_yaml.status_code)
if resp_yaml.status_code == 200:
    try:
        spec = yaml.safe_load(resp_yaml.data)
        print("OpenAPI parsed successfully.")
        print("Title:", spec['info']['title'])
        print("Total paths:", len(spec['paths']))
    except Exception as e:
        print("Error parsing YAML:", e)
