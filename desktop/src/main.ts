import { invoke } from "@tauri-apps/api/core";

const statusEl = document.getElementById("status")!;
const errorEl = document.getElementById("error")!;
const errorCard = document.getElementById("error-card")!;
const errorSummary = document.getElementById("error-summary")!;
const spinnerEl = document.getElementById("spinner")!;
const retryEl = document.getElementById("retry")!;

async function sleep(ms: number): Promise<void> {
  await new Promise((r) => setTimeout(r, ms));
}

function friendlyError(raw: string): string {
  const msg = raw.toLowerCase();
  if (msg.includes("500") || msg.includes("internal server")) {
    return "The local lab started but returned an error. Retry, or reinstall v4.0.4+ if PHP on this PC is conflicting.";
  }
  if (msg.includes("payload missing")) {
    return "The lab files were not bundled. Reinstall PC Lab Kit from the latest GitHub release.";
  }
  if (msg.includes("connect") || msg.includes("not ready") || msg.includes("empty response")) {
    return "The lab did not become ready in time. Retry, or check that nothing else is blocking localhost.";
  }
  return "The local laboratory failed to start. Retry, or reinstall from GitHub Releases.";
}

async function boot(): Promise<void> {
  statusEl.textContent = "Starting lab…";
  errorCard.hidden = true;
  spinnerEl.style.display = "";
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
        statusEl.textContent = "Starting lab…";
        await sleep(250);
        continue;
      }
      break;
    }
  }

  spinnerEl.style.display = "none";
  statusEl.textContent = "Could not start PC Lab Kit";
  errorCard.hidden = false;
  errorSummary.textContent = friendlyError(lastError);
  errorEl.textContent = lastError;
}

retryEl.addEventListener("click", () => {
  void boot();
});

boot();
