const API_BASE = "/api";
const MIN_FREQ = 0;
const MAX_FREQ = 30_000_000;
const MAX_ZOOM = 14;
let is_recording = false, start_error = false

function updateBandwidthInfo() {
    const type = (document.getElementById('typeSelect')! as HTMLSelectElement).value;
    const zoomInput = document.getElementById('zoomInput') as HTMLInputElement;
    const zoom = parseInt(zoomInput.value, 10);
    const freqInput = parseFloat((document.getElementById('freqInput')! as HTMLInputElement).value) * 1000; // kHz → Hz
    
    const bandwidthLine = document.getElementById('bandwidthLine')! as HTMLBodyElement;
    const minFreqLine = document.getElementById('minFreqLine')! as HTMLBodyElement;
    const maxFreqLine = document.getElementById('maxFreqLine')! as HTMLBodyElement;
    const zoomWarning = document.getElementById('zoomWarning')! as HTMLBodyElement;
    const startBtn = document.getElementById('startBtn')! as HTMLButtonElement;

    const { bandwidth, selection_freq_min, selection_freq_max, zoom_invalid, error_messages } = calcFreqRange(freqInput, zoom, type)
    
    if (error_messages.length > 0) {
        zoomWarning.style.display = 'block';
        zoomWarning.innerHTML = error_messages.join('<br><br>');
        start_error = true
        startBtn.disabled = is_recording || start_error;
    } else {
        zoomWarning.style.display = 'none';
        start_error = false
        startBtn.disabled = is_recording || start_error;
    }

    if (!zoom_invalid) {
        bandwidthLine.textContent = "Bandwidth: " + format_freq(bandwidth);
        minFreqLine.textContent = "Min: " + format_freq(selection_freq_min);
        maxFreqLine.textContent = "Max: " + format_freq(selection_freq_max);
    
    }
    else {
        bandwidthLine.textContent = 'Bandwidth: --';
        minFreqLine.textContent = 'Min: --';
        maxFreqLine.textContent = 'Max: --';
    }
}

function isNrValid(nr: number, nr_name: string) {
    let nr_valid = true, nr_error_messages = [];
    if (isNaN(nr)) {
        nr_error_messages.push(nr_name + " is not a number.");
        nr_valid = false;
    } 
    return { nr_valid: nr_valid, nr_error_messages: nr_error_messages };
}

function isZoomValid(zoom: number) {
    let zoom_valid = true, zoom_error_messages = [];
    const { nr_valid, nr_error_messages } = isNrValid(zoom, "Zoom")
    zoom_error_messages.push(...nr_error_messages)
    if (!nr_valid) {
        zoom_valid = false;
    } 
    else {
        if (zoom < 0) {
            zoom_error_messages.push(`Zoom is too low: ${zoom}. Minimum is 0.`);
            zoom_valid = false;
        }
        else if (zoom > MAX_ZOOM) {
            zoom_error_messages.push(`Zoom is too high: ${zoom}. Maximum is ${MAX_ZOOM}.`);
            zoom_valid = false;
        }
    }
    return {zoom_valid: zoom_valid, zoom_error_messages: zoom_error_messages};
}

function calcFreqRange(center_freq_hz: number, zoom: number, mode: string) { // Int, Int, Str => Band: Int, Min: Int, Max: Int, Invalid: bool, error: []
    let bandwidth = 0, selection_freq_min = 0, selection_freq_max = 0, freq_range_invalid = false, error_messages = [];

    const { nr_valid, nr_error_messages } = isNrValid(center_freq_hz, "Frequency")
    error_messages.push(...nr_error_messages)
    if (!nr_valid) {
        return { bandwidth: 0, selection_freq_min: 0, selection_freq_max: 0, freq_range_invalid: null, zoom_invalid: false, error_messages: error_messages };
    }

    if (mode == "png") {
        const {zoom_valid, zoom_error_messages} = isZoomValid(zoom);
        error_messages.push(...zoom_error_messages);
        if (!zoom_valid) {
            return { bandwidth: 0, selection_freq_min: 0, selection_freq_max: 0, freq_range_invalid: null, zoom_invalid: true, error_messages: error_messages };
        }

        bandwidth = (MAX_FREQ - MIN_FREQ) / Math.pow(2, zoom);
    }
    else if (mode == "iq") {
        bandwidth = 12_000
    }
    else {
        error_messages.push(`Invalid type: ${mode}`)
        return { bandwidth: 0, selection_freq_min: 0, selection_freq_max: 0, freq_range_invalid: null, zoom_invalid: false, error_messages: error_messages };
    }

    selection_freq_max = center_freq_hz + bandwidth / 2;
    selection_freq_min = center_freq_hz - bandwidth / 2;

    if (selection_freq_max > MAX_FREQ) {
        error_messages.push("Frequency range exceeds MAX_FREQ " + format_freq(MAX_FREQ)+ ". Selected max = " + format_freq(selection_freq_max));
        freq_range_invalid = true;
    }
    if (selection_freq_min < MIN_FREQ) {
        error_messages.push("Frequency range below MIN_FREQ " + format_freq(MIN_FREQ) + ". Selected min = " + format_freq(selection_freq_min));
        freq_range_invalid = true;
    }

    return { bandwidth: bandwidth, selection_freq_min: selection_freq_min, selection_freq_max: selection_freq_max, freq_range_invalid: freq_range_invalid, zoom_invalid: false, error_messages: error_messages };
}

function handleTypeChange() {
    const type = (document.getElementById('typeSelect')! as HTMLSelectElement).value;
    const zoomInput = document.getElementById('zoomInput') as HTMLInputElement;
    zoomInput.disabled = (type !== 'png');
}

function format_freq(freq_hz: number) {
    if (Math.abs(freq_hz) < 1000) {
        let freq_hz_str = freq_hz.toFixed(0)
        return `${freq_hz_str} Hz`
    }
    else if (Math.abs(freq_hz) >= 1000 && Math.abs(freq_hz) < 1_000_000) {
        let freq_khz = (freq_hz / 1000).toFixed(1)
        return `${freq_khz} kHz`
    }
    else {
        let freq_mhz = (freq_hz / 1_000_000).toFixed(1)
        return `${freq_mhz} MHz`
    }
}

async function getRecorderStatus() {
    try {
        const response = await fetch(`${API_BASE}/recorder/status`);
        const data = await response.json();

        const statusElement = document.getElementById('recorderStatus')! as HTMLBodyElement;
        const startedAtElement = document.getElementById('startedAt')! as HTMLBodyElement;
        const logsContainer = document.getElementById('logsContainer')! as HTMLBodyElement;
        const logTableBody = document.getElementById('logTableBody')! as HTMLBodyElement;

        is_recording = data.recording;
        (document.getElementById('startBtn')! as HTMLButtonElement).disabled = is_recording || start_error;
        (document.getElementById('stopBtn')! as HTMLButtonElement).disabled = !is_recording;
        if (data.recording) {
            statusElement.textContent = "Recording";
            statusElement.style.color = "var(--accent-color)";
            
        } else {
            statusElement.textContent = "Not Recording";
            statusElement.style.color = "var(--text-color-muted)";
        }

        if (data.started_at) {
            const date = new Date(data.started_at * 1000);
            startedAtElement.textContent = `Started at: ${date.toLocaleString(undefined, { hour12: false })}`;
        } 
        else {
            startedAtElement.textContent = "Started at: --/--/--, --:--:--";
        }

        if (data.last_logs && data.last_logs.length > 0) {
            logsContainer.style.display = "flex";
            logTableBody.innerHTML = "";
            for (const log of data.last_logs) {
                const row = document.createElement("tr");
                const timestampCell = document.createElement("td");
                const timestamp = new Date(log.timestamp * 1000).toLocaleString(undefined, { hour12: false });
                timestampCell.textContent = timestamp;
                row.appendChild(timestampCell);
                const logCell = document.createElement("td");
                logCell.textContent = log.data;
                row.appendChild(logCell);
                logTableBody.appendChild(row);
            }
        } else {
            logsContainer.style.display = "none";
        }
    }
    catch (err) {
        console.error("Failed to fetch recorder status:", err);
    }
}

async function startRecording() {
    const rec_type = (document.getElementById('typeSelect')! as HTMLSelectElement).value;
    const freq_khz = parseFloat((document.getElementById('freqInput')! as HTMLInputElement).value);
    const freq_hz = Math.round(freq_khz * 1000); // kHz → Hz
    const zoom = parseInt((document.getElementById('zoomInput')! as HTMLInputElement).value, 10);
    const autostop = parseInt((document.getElementById('autostopInput')! as HTMLInputElement).value, 10) || 0;

    const body = { rec_type, frequency: freq_hz, autostop, zoom };

    try {
        const response = await fetch(`${API_BASE}/recorder/start`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body)
        });
        const data = await response.json();
        (document.getElementById('messageBox')! as HTMLBodyElement).textContent = data.message;
        await getRecorderStatus();
    } catch (err) {
        (document.getElementById('messageBox')! as HTMLBodyElement).textContent = "Failed to start recorder.";
    }
}

async function stopRecording() {
    try {
        const response = await fetch(`${API_BASE}/recorder/stop`, { method: 'POST' });
        const data = await response.json();
        (document.getElementById('messageBox')! as HTMLBodyElement).textContent = data.message;
        await getRecorderStatus();
    } catch (err) {
        (document.getElementById('messageBox')! as HTMLBodyElement).textContent = "Failed to stop recorder.";
    }
}

getRecorderStatus();
setInterval(getRecorderStatus, 1000);

// Update bandwidth info when freq or zoom changes
(document.getElementById('freqInput')! as HTMLInputElement).addEventListener('input', updateBandwidthInfo);
(document.getElementById('zoomInput')! as HTMLInputElement).addEventListener('input', updateBandwidthInfo);
(document.getElementById('typeSelect')! as HTMLSelectElement).addEventListener('change', updateBandwidthInfo);
updateBandwidthInfo();
(window as any).startRecording = startRecording;
(window as any).stopRecording = stopRecording;
(window as any).handleTypeChange = handleTypeChange;
