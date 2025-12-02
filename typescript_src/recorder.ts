const API_URL = "https://kiwisdr.local/api";
const MIN_FREQ = 0;
const MAX_FREQ = 30_000_000;
const MAX_ZOOM = 14;
const REFRESH_INTERVAL_MS = 5000;

// --- DOM Elements ---
const apiStatusEl = document.getElementById('api-status') as HTMLBodyElement;
const createJobForm = document.getElementById('create-job-form') as HTMLFormElement;
const createJobBtn = document.getElementById('create-job-btn') as HTMLButtonElement;
const jobsTableBody = document.getElementById('jobs-table-body') as HTMLTableElement;
const freqRangeEl = document.getElementById('freq-range') as HTMLBodyElement;
const bandwidthEl = document.getElementById('bandwith') as HTMLBodyElement;
const warningEl = document.getElementById('warning') as HTMLBodyElement;

// Form inputs
const recTypeInput = document.getElementById('rec_type') as HTMLSelectElement;
const frequencyInput = document.getElementById('frequency') as HTMLInputElement;
const zoomInput = document.getElementById('zoom') as HTMLInputElement;
const durationInput = document.getElementById('duration') as HTMLInputElement;
const intervalInput = document.getElementById('interval') as HTMLInputElement;

type RecordingType = 'png' | 'iq';

interface Log {
    timestamp: number;
    data: string;
}

type Logs = Log[];

interface RecorderSettings {
    rec_type: RecordingType;
    frequency: number;
    zoom?: number;
    duration: number;
    interval?: number | null;
}

interface Job {
    job_id: number;
    running: boolean;
    started_at: number | null;
    next_run_start: number | null;
    logs: Logs;
    settings: RecorderSettings;
}

type JobList = Job[];

let is_recording = false, start_error = false

function updateBandwidthInfo() {
    const { bandwidth, selection_freq_min, selection_freq_max, zoom_invalid, error_messages } = calcFreqRange(Number(frequencyInput.value) * 1000, Number(zoomInput.value), recTypeInput.value)
    
    if (error_messages.length > 0) {
        warningEl.textContent = error_messages.join('<br><br>');
        start_error = true
        createJobBtn.disabled = is_recording || start_error;
    } else {
        warningEl.textContent = '';
        start_error = false
        createJobBtn.disabled = is_recording || start_error;
    }
    if (!zoom_invalid) {
        bandwidthEl.textContent = "Bandwidth: " + format_freq(bandwidth);
        freqRangeEl.textContent = "Range: " + format_freq(selection_freq_min) + ' - ' + format_freq(selection_freq_max);
    }
    else {
        freqRangeEl.textContent = 'Range: ---- Hz - ---- Hz';
        bandwidthEl.textContent = 'Bandwidth: ---- Hz';
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

function formatTime(unixTime: number | null) {
    if (unixTime == null) {
        return "None"
    }
    const date = new Date((unixTime * 1000));
    return date.toLocaleString(undefined, { hour12: false })
}

async function getAllJobStatus() {
    try {
        const response = await fetch(`${API_URL}/recorder/status`);
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        const joblist: JobList = await response.json();
        renderJobList(joblist);
    }
    catch (err) {
        console.error("Failed to fetch recorder status:", err);
    }
}

async function renderJobList(jobs: JobList) {
    jobsTableBody.innerHTML = ''; // Clear existing table

    if (jobs.length == 0) {
        jobsTableBody.innerHTML = `<tr><td colspan="10" style="text-align:center;">No active jobs found.</td></tr>`;
        return;
    }

    for (const job of jobs) {
        const tr = document.createElement('tr');
        tr.setAttribute('data-job-id', `${job.job_id}`);
        
        const statusText: string = job.running ? 'Recording' : 'Stoped';
        const statusColor: string = job.running ? 'var(--green)' : 'var(--red)';
        const settings: string = 
        `
        <br>Freq: ${job.settings.rec_type}</br>
        <br>Freq: ${format_freq(job.settings.frequency)}</br>
        `;
        
        tr.innerHTML = `
            <td>${job.job_id}</td>
            <td style="color: ${statusColor}; font-weight: bold;">${statusText}</td>
            <td>${settings}</td>
            <td>${formatTime(job.started_at)}</td>
            <td>${formatTime(job.next_run_start)}</td>
            <td>
                <div class="button-group">
                    <button class="btn-stop" data-job-id="${job.job_id}" ${!job.running ? 'disabled' : ''}>Stop</button>
                    <button class="btn-logs" data-job-id="${job.job_id}">Logs</button>
                    <button class="btn-remove" data-job-id="${job.job_id}">Remove</button>
                </div>
            </td>
        `;
        jobsTableBody.appendChild(tr);
    }
}

async function handleCreateJob(event: SubmitEvent) {
    event.preventDefault();
    const rec_type = recTypeInput.value;
    const frequency = Math.round(parseFloat(frequencyInput.value) * 1000);
    const zoom = parseInt(zoomInput.value, 10);
    const duration = parseInt(durationInput.value, 10);
    const interval = parseInt(intervalInput.value, 10);

    const body = { rec_type, frequency, zoom, duration, interval };

    try {
        const response = await fetch(`${API_URL}/recorder/start`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body)
        });
        const data = await response.json();
        console.log(data);
        await getAllJobStatus();
    } catch (err) {
        warningEl.textContent = `Failed to start recorder. Error: ${err}`;
    }
}

async function checkApiStatus() {
    try {
        const response = await fetch(`${API_URL}/`);
        if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
        
        const text = await response.text();
        apiStatusEl.textContent = `API Status: ${text}`;
        apiStatusEl.className = 'online';
    } catch (error) {
        console.error('API status check failed:', error);
        apiStatusEl.textContent = 'API Status: OFFLINE';
        apiStatusEl.className = 'offline';
    }
}

document.addEventListener('DOMContentLoaded', () => {
    checkApiStatus();
    getAllJobStatus();
    setInterval(getAllJobStatus, REFRESH_INTERVAL_MS);

    // Update bandwidth info when freq or zoom changes
    frequencyInput.addEventListener('input', updateBandwidthInfo);
    zoomInput.addEventListener('change', updateBandwidthInfo);
    createJobForm.addEventListener('submit', handleCreateJob)
    updateBandwidthInfo();
});
