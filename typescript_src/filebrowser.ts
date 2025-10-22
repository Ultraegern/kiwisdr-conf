const DOWNLOAD_URL = '/recorder/download/';

// List of file extensions that can be viewed in the browser
const viewableExtensions = ['txt', 'png'];

interface FileEntry {
    name: String, 
    size: String, 
    date: Date
}

async function fetchFileList() {
    try {
        const res = await fetch(DOWNLOAD_URL);
        const text = await res.text();
        const doc = new DOMParser().parseFromString(text, 'text/html');

        const pre = doc.querySelector('pre');
        if (!pre) {
            (document.getElementById('file-table')! as HTMLTableElement).innerHTML = "<tr><td colspan='4'>No files found.</td></tr>";
            return;
        }

        const lines = pre.innerText.split('\n').slice(3); // Skip header lines

        let files: FileEntry[] = [];

        for (const line of lines) {
            // Match lines like: file123.wav  15-Oct-2025 13:50  100M
            const match = line.match(/(\S+)\s+(\d{2})-(\w{3})-(\d{4})\s+(\d{2}):(\d{2})\s+([\d.]+\w?)/);
            if (!match) continue;

            const [_, name, day, monthStr, year, hour, minute, size] = match;

            const monthMap: Record<string, number> = {
                Jan: 0, Feb: 1, Mar: 2, Apr: 3, May: 4, Jun: 5,
                Jul: 6, Aug: 7, Sep: 8, Oct: 9, Nov: 10, Dec: 11
            };
            if (name === undefined || size === undefined || monthStr === undefined) continue;
            const month = monthMap[monthStr];
            if (month === undefined) continue;
            const fileDate = new Date(Number(year), month, Number(day), Number(hour), Number(minute));

            files.push({ name, size, date: fileDate });
        };

        // Sort by date descending (newest first)
        files.sort((a, b) => b.date.getTime() - a.date.getTime());

        // Populate the table
        const tbody = document.querySelector('#file-table tbody')!;
        files.forEach(file => {
            const tr = document.createElement('tr');
            const pad = (n: number): string => n.toString().padStart(2, '0');
            const d = file.date;
            const formattedDate = `${pad(d.getHours())}:${pad(d.getMinutes())} ${pad(d.getDate())}/${pad(d.getMonth() + 1)}-${d.getFullYear()}`;
            const fileName = String(file.name);
            // Check file extension for viewable types
            const ext = file.name.split('.').pop()?.toLowerCase() ?? '';
            const viewButton = viewableExtensions.includes(ext)
            ? `<a href="${DOWNLOAD_URL + encodeURIComponent(fileName)}" target="_blank"><button>View</button></a>`
            : '';

            tr.innerHTML = `
                <td>${file.name}</td>
                <td>${formattedDate}</td>
                <td>${file.size}B</td>
                <td>
                    <div class="button-group">
                    ${viewButton}
                    <a href="${DOWNLOAD_URL + encodeURIComponent(fileName)}" download><button>Download</button></a>
                    </div>
                </td>
            `;

            tbody.appendChild(tr);
        });
    } 
    catch (err) {
        console.error('Error loading file list:', err);
        const tbody = document.querySelector('#file-table tbody');
        const message = err instanceof Error ? err.message : String(err);
        if (tbody) {
            tbody.innerHTML = `<tr><td colspan="4">Error: ${message}</td></tr>`;
        }
    }

}

fetchFileList();