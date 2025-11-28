# KiwiSDR Recorder Job Scheduler API Map

This document outlines the available endpoints for interacting with the KiwiSDR Recorder Job Scheduler service.

The service manages the scheduling, execution, and monitoring of recording jobs using the `kiwirecorder.py` tool.

## Data Structures

### 1. `RecorderSettings` (Request/Input)

Defines the parameters for a new recording job.

| **Field Name** | **Type** | **Description** | **Required** | **Default** | 
 | ----- | ----- | ----- | ----- | ----- | 
| `rec_type` | `string` (`"png"` or `"iq"`) | The type of recording output. | Yes | \- | 
| `frequency` | `u32` (Hz) | The center frequency for the recording. | Yes | \- | 
| `zoom` | `u8` | Zoom level for PNG recordings (0-14). Ignored for IQ. | No | `0` | 
| `duration` | `u16` (seconds) | The length of the recording. `0` means infinite duration (until manually stopped). | Yes | \- | 
| `interval` | `Option<u32>` (seconds) | If set, the job will restart every `interval` seconds after the previous run finishes. `null` or omission means the job runs once. | No | `null` | 

Freq's are calculated like this:
```
MIN_FREQ = 0;
MAX_FREQ = 30_000_000;
bandwidth = (MAX_FREQ - MIN_FREQ) / 2 ^ zoom; 
selection_freq_max = center_freq + (bandwidth / 2);
selection_freq_min = center_freq - (bandwidth / 2);
```

**Example JSON Request Body:**
```json
{
  "rec_type": "png",
  "frequency": 14204000,
  "zoom": 10,
  "duration": 60,
  "interval": 3600
}
```

### 2. `Log`

A single log entry captured from the running KiwiSDR process (stdout/stderr).

| **Field Name** | **Type** | **Description** | 
 | ----- | ----- | ----- | 
| `timestamp` | `u64` (Unix) | The time the log entry was captured. | 
| `data` | `string` | The log message (truncated to 200 characters). | 

### 3. `JobStatus` (Response/Output)

The current state and metadata of a recorder job.

| **Field Name** | **Type** | **Description** | 
 | ----- | ----- | ----- | 
| `job_id` | `u32` | Unique identifier for the job. | 
| `running` | `boolean` | `true` if the job's child process is currently active. | 
| `started_at` | `Option<u64>` (Unix) | Timestamp when the current/last run started. `null` if no run has started. | 
| `next_run_start` | `Option<u64>` (Unix) | Expected time (if interval is set) for the next run. `null` if it's a one-time job or has no future runs scheduled. | 
| `logs` | `Array<Log>` | A deque of the most recent log entries (truncated to 20 Log's). | 
| `settings` | `RecorderSettings` | The job's settings. | 

## API Endpoints

### 1. Status Check (Root)

| **Method** | **Path** | **Description** | 
 | ----- | ----- | ----- | 
| `GET` | `/api/` | Checks if the API service is running. | 

**Response:** `200 OK` with body `"Api is Online"`.

### 2. Start a New Recorder Job

| **Method** | **Path** | **Description** | 
 | ----- | ----- | ----- | 
| `POST` | `/api/recorder/start` | Creates a new job, schedules it, and immediately spawns the first recorder process. | 

**Request Body:** `RecorderSettings` JSON object.

**Constraints/Validation:**

* Maximum of **3 active job slots** are allowed (`MAX_JOB_SLOTS`).

* The frequency range (based on `frequency` and `zoom`) must be within the supported limits (`0` to `30,000,000` Hz).

**Response (Success):** `200 OK` with `JobStatus` JSON for the newly created job.  
**Response (Failure):** `400 Bad Request` with an error message (e.g., "All recorder slots are full", "Zoom too high", "The selected frequency range exceeds...").

### 3. Get All Recorder Statuses

| **Method** | **Path** | **Description** | 
 | ----- | ----- | ----- | 
| `GET` | `/api/recorder/status` | Retrieves the status summary for all managed recorder jobs. | 

**Response:** `200 OK` with a JSON array of `JobStatus` objects.

### 4. Get Single Recorder Status

| **Method** | **Path** | **Description** | 
 | ----- | ----- | ----- | 
| `GET` | `/api/recorder/status/{job_id}` | Retrieves the status for a specific job. | 

**Path Parameters:**

* `job_id`: The ID of the job to retrieve (u32).

**Response (Success):** `200 OK` with `JobStatus` JSON.  
**Response (Failure):** `400 Bad Request` with `{ "message": "Job not found: job_id not valid" }`.

### 5. Stop a Running Job

| **Method** | **Path** | **Description** | 
 | ----- | ----- | ----- | 
| `POST` | `/api/recorder/stop/{job_id}` | Sends a kill signal to the running child process, stopping the current recording. If the job has an `interval` set, it will be automatically started by the job scheduler for the next run. | 

**Path Parameters:**

* `job_id`: The ID of the job to stop (u32).

**Response (Success):** `200 OK` with the updated `JobStatus` JSON.  
**Response (Failure):** `400 Bad Request` with `{ "message": "Job not found: job_id not valid" }`.

### 6. Remove a Recorder Job

| **Method** | **Path** | **Description** | 
 | ----- | ----- | ----- | 
| `DELETE` | `/api/recorder/{job_id}` | Stops a running job (if necessary) and permanently removes it from the scheduler's hash map. | 

**Path Parameters:**

* `job_id`: The ID of the job to delete (u32).

**Response (Success):** `200 OK` with `{ "message": "Recorder deleted successfully" }`.  
**Response (Failure):** `400 Bad Request` with `{ "message": "Job not found: job_id not valid" }`.
