import requests

try:
    print("Trying with verify=True")
    res = requests.get('https://vnedgshbefpctjyzpqlm.supabase.co/auth/v1/health')
    print("Status:", res.status_code)
    print("Body:", res.text)
except Exception as e:
    print("Error verify=True:", e)

try:
    print("\nTrying with verify=False")
    res = requests.get('https://vnedgshbefpctjyzpqlm.supabase.co/auth/v1/health', verify=False)
    print("Status:", res.status_code)
    print("Body:", res.text)
except Exception as e:
    print("Error verify=False:", e)
