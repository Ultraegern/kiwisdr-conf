from flask import Flask, request, jsonify
import subprocess
from typing import Optional, Dict, Any

app: Flask = Flask(__name__)

# You can store the process here to stop it later
recording_process: Optional[subprocess.Popen] = None

@app.route('/recorder/start', methods=['POST'])
def start_recording() -> tuple[Dict[str, str], int] | Dict[str, str]:
    global recording_process
    try:
        data: dict[str, Any] = request.get_json()  # type: ignore
        frequency: str = str(data.get('frequency'))
        bandwidth: str = str(data.get('bandwidth'))
        duration: str = str(data.get('duration'))

        # Build the command line arguments for kiwiclient
        cmd: list[str] = [
            'kiwiclient',  # Replace with the actual command
            '--frequency', frequency,
            '--bandwidth', bandwidth,
            '--duration', duration
        ]

        # Start the recording process
        recording_process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        return {"message": f"Recording started at {frequency} Hz, {bandwidth} kHz bandwidth for {duration} seconds."}
    except Exception as e:
        return {"message": f"Error starting recording: {e}"}, 500

@app.route('/recorder/stop', methods=['POST'])
def stop_recording() -> tuple[Dict[str, str], int] | Dict[str, str]:
    global recording_process
    try:
        if recording_process:
            recording_process.terminate()  # Stops the process
            recording_process = None
            return {"message": "Recording stopped successfully."}
        else:
            return {"message": "No recording is running."}, 400
    except Exception as e:
        return {"message": f"Error stopping recording: {e}"}, 500

if __name__ == '__main__':
    app.run(debug=True)
