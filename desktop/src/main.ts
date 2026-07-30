import { invoke } from "@tauri-apps/api/core";

const statusEl = document.getElementById("status")!;
const errorEl = document.getElementById("error")!;
const spinnerEl = document.getElementById("spinner")!;

async function sleep(ms: number): Promise<void> {
  await new Promise((r) => setTimeout(r, ms));
}

async function boot(): Promise<void> {
  statusEl.textContent = "Starting local laboratory…";
  let lastError = "unknown error";

  for (let attempt = 0; attempt < 120; attempt++) {
    try {
      const url = await invoke<string>("get_lab_url");
      statusEl.textContent = "Opening lab…";
      window.location.replace(url);
      return;
    } catch (err) {
      lastError = String(err);
      const msg = lastError.toLowerCase();
      if (msg.includes("still starting")) {
        statusEl.textContent = "Starting local laboratory…";
        await sleep(250);
        continue;
      }
      // Hard failure from Rust
      break;
    }
  }

  spinnerEl.style.display = "none";
  statusEl.textContent = "Could not start PC Lab Kit";
  errorEl.hidden = false;
  errorEl.textContent = lastError;
}

boot();
