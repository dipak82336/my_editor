import subprocess
import json
import re
import sys

def run_flutter_tests():
    """
    Runs flutter tests and parses the output.
    """
    # Set the PATH to include flutter bin just in case it's not picked up,
    # though it should be if installed in previous steps.
    # We assume 'flutter' is in the PATH.

    command = ["flutter", "test", "test/widget_test.dart", "--machine"]

    try:
        # Run the command and capture stdout/stderr
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        stdout, stderr = process.communicate()

        if process.returncode == 0:
            print("SUCCESS")
        else:
            print("FAILURE")
            parse_failure(stdout, stderr)

    except FileNotFoundError:
        print("Error: 'flutter' command not found. Please ensure Flutter is installed and in your PATH.")
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        sys.exit(1)

def parse_failure(stdout, stderr):
    """
    Parses the JSON output from flutter test --machine to extract failure details.
    """
    # Each line in stdout is a JSON object
    lines = stdout.strip().split('\n')
    error_found = False

    for line in lines:
        if not line.strip():
            continue
        try:
            event = json.loads(line)

            # Handle if event is a list (though typically it's a dict)
            if isinstance(event, list):
                for item in event:
                    if process_event(item):
                        error_found = True
            elif isinstance(event, dict):
                if process_event(event):
                    error_found = True

        except json.JSONDecodeError:
            continue

    # If no JSON error event was found, print stderr or raw stdout fallback
    if not error_found:
        print("Could not parse JSON error details. Raw Output:")
        print(stdout)
        if stderr:
            print("Stderr:")
            print(stderr)

def process_event(event):
    if event.get('type') == 'testDone' and event.get('result') == 'failed':
        return False # Wait for 'error' event

    if event.get('type') == 'error':
            error_message = event.get('error', '')
            stack_trace = event.get('stackTrace', '')
            print(f"Error: {error_message}")
            # print(f"Stack Trace:\n{stack_trace}")
            return True
    return False

if __name__ == "__main__":
    run_flutter_tests()