# Python 3.9
from flask import Flask, request, jsonify
import subprocess
from typing import Optional, Dict, Any
import os
import json
from pathlib import Path
from datetime import datetime

app: Flask = Flask(__name__)

recording_nr: int = 0

@app.route('/api/status', methods=['GET'])
def is_alive() -> Dict[str, str]:
    return {"message": "API is online"}

# You can store the process here to stop it later
recording_process: Optional[subprocess.Popen] = None

@app.route('/api/recorder/start', methods=['POST'])
def start_recording() -> Any: #Union[Tuple[Dict[str, str], int], Dict[str, str]]:
    global recording_process, recording_nr
    try:
        data: dict[str, Any] = request.get_json()  # type: ignore
        duration: str = str(data.get('duration'))
        autostop: bool = not (duration == "0")
        # python3 kiwirecorder.py -s <kiwi_host> -p <port> -m iq --kiwi-wav -d <dir> --filename <filename> --station <filename nr 2>
        cmd = [
            'python3', 'kiwirecorder.py',
            '-s', '127.0.0.1',
            '-p', '8073',
            '-m', 'iq',
            '--kiwi-wav',
            '-d', '/var/recorder/recorded-files/',
            '--filename', "KiwiRecording",
            '--station', str(recording_nr).zfill(4) 
        ]

        recording_process = subprocess.Popen(
            cmd,
            cwd='/usr/local/src/kiwiclient/',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )

        recording_nr = (recording_nr + 1) % 10000  # Wrap around after 9999
        if autostop:
            # If autostop is enabled, wait for the specified duration and then stop the recording
            recording_process.wait(timeout=int(duration))
            recording_process.terminate()
            recording_process = None
            rebuild_file_index_list()
            return {"message": f"Recording has started, and will stop in {duration} seconds."}
        else:
            return {"message": "Recording has started and will continue until stopped manually."}    
    except Exception as e:
        return {"message": f"Error starting recording: {e}"}, 500

@app.route('/api/recorder/stop', methods=['POST'])
def stop_recording() -> Any: #Union[Tuple[Dict[str, str], int], Dict[str, str]]:
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
    app.run(debug=True, host='0.0.0.0', port=5000)
