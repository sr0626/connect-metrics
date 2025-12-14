import json

def lambda_handler(event, context):
    #print(f"event: {json.dumps(event, separators=(",", ":"), ensure_ascii=False)}")
    # EventBridge payload: just print the event.detail as compact JSON
    # If you want full envelope, replace event.get("detail", {}) with event
    payload = event.get("detail", {})
    print("detail: ", json.dumps(payload, separators=(",", ":"), ensure_ascii=False))
    return {"ok": True, "size": len(json.dumps(payload))}