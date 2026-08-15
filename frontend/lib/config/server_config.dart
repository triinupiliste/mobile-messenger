// Single place to point the app at the backend. Update this when your ngrok
// URL changes (free ngrok URLs are re-assigned every time you restart it).
//
// - USB-tethered single device + `adb reverse tcp:5000 tcp:5000`:
//     'http://127.0.0.1:5000'
// - Two+ real phones on their own networks, backend exposed via ngrok:
//     'https://<your-subdomain>.ngrok-free.app'
const String serverBaseUrl = 'https://747e-185-68-210-241.ngrok-free.app';
