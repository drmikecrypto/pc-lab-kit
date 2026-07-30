<?php

declare(strict_types=1);

namespace App\Controllers;

/**
 * Serves portable app archives and the Windows probe ZIP.
 */
class DownloadController
{
    private const WINDOWS_APP = 'pc-lab-kit-windows-x64.zip';

    private const LINUX_APP = 'pc-lab-kit-linux-x64.tar.gz';

    private const PROBE_ZIP = 'pc-lab-kit-probe-windows.zip';

    private function downloadsRoot(): string
    {
        return dirname(__DIR__, 2) . '/public/downloads';
    }

    public function windowsApp(): void
    {
        $this->sendFile(self::WINDOWS_APP, 'application/zip', 'Windows app not built yet. Run scripts/build-app-windows.ps1');
    }

    public function linuxApp(): void
    {
        $this->sendFile(self::LINUX_APP, 'application/gzip', 'Linux app not built yet. Run scripts/build-app-linux.sh');
    }

    /** Stream the Windows probe agent bundle. */
    public function probeWindows(): void
    {
        $this->sendFile(self::PROBE_ZIP, 'application/zip', 'Probe bundle not built yet. Run scripts/build-agent-bundle.ps1');
    }

    private function sendFile(string $filename, string $contentType, string $missingMessage): void
    {
        $path = $this->downloadsRoot() . '/' . $filename;
        if (!is_file($path)) {
            http_response_code(404);
            header('Content-Type: text/plain; charset=utf-8');
            echo $missingMessage;

            exit;
        }

        header('Content-Type: ' . $contentType);
        header('Content-Disposition: attachment; filename="' . $filename . '"');
        header('Content-Length: ' . (string) filesize($path));
        readfile($path);
        exit;
    }
}
