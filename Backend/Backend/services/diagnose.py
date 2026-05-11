import sys
import os

# Add Backend root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

print("Python:", sys.version)
print("Platform:", sys.platform)
print("Working dir:", os.getcwd())
print()

# Test 1: imports
print("=== TESTING IMPORTS ===")
try:
    import tzlocal
    print("✅ tzlocal:", tzlocal.get_localzone())
except Exception as e:
    print("❌ tzlocal FAILED:", e)

try:
    from dateutil import parser
    print("✅ dateutil OK")
except Exception as e:
    print("❌ dateutil FAILED:", e)

# Test 2: parse_natural_reminder
print()
print("=== TESTING PARSER ===")
try:
    from services.assistant_service import parse_natural_reminder
    result = parse_natural_reminder("set a reminder 26 march 5 pm meeting")
    print("✅ Parser result:", result)
except Exception as e:
    import traceback
    print("❌ Parser FAILED:")
    traceback.print_exc()

# Test 3: create_reminder signature
print()
print("=== TESTING create_reminder SIGNATURE ===")
try:
    from services.reminder_service import create_reminder
    import inspect
    sig = inspect.signature(create_reminder)
    params = list(sig.parameters.keys())
    print("✅ create_reminder params:", params)
    print()
    # Check if all required params exist
    required = ['user_id', 'task', 'time_text', 'time_display', 'source', 'recurring_type', 'user_timezone']
    for p in required:
        if p in params:
            print(f"   ✅ '{p}' — found")
        else:
            print(f"   ❌ '{p}' — MISSING from create_reminder!")
except Exception as e:
    import traceback
    print("❌ create_reminder import FAILED:")
    traceback.print_exc()

# Test 4: try calling create_reminder with dummy data
print()
print("=== TESTING create_reminder CALL ===")
try:
    from services.reminder_service import create_reminder
    from datetime import datetime
    import inspect
    sig = inspect.signature(create_reminder)
    params = list(sig.parameters.keys())
    print("Calling create_reminder with test data...")

    # Build kwargs based on what params exist
    kwargs = {"user_id": "test_user_123", "task": "Meeting"}
    if "time_text" in params:
        kwargs["time_text"] = datetime(2026, 3, 26, 17, 0)
    if "time_display" in params:
        kwargs["time_display"] = "Mar 26 • 05:00 PM"
    if "source" in params:
        kwargs["source"] = "assistant"
    if "recurring_type" in params:
        kwargs["recurring_type"] = "none"
    if "user_timezone" in params:
        kwargs["user_timezone"] = "Asia/Calcutta"

    print("Params being sent:", list(kwargs.keys()))
    # Don't actually call — just show what would be sent
    print("✅ Would call create_reminder with:", kwargs)

except Exception as e:
    import traceback
    print("❌ FAILED:")
    traceback.print_exc()

print()
print("=== DONE — paste this output for diagnosis ===")