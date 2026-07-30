<?php

declare(strict_types=1);

namespace App\Controllers;

/**
 * Serves installable desktop apps and the optional Windows probe ZIP.
 */
class DownloadController
{
    private const WINDOWS_SETUP = 'PcLabKit-Setup-Windows-x64.exe';

    private const LINUX_APPIMAGE = 'PcLabKit-Linux-x64.AppImage';

    private const PROBE_ZIP = 'pc-lab-kit-probe-windows.zip';

    private function downloadsRoot(): string
    {
        return dirname(__DIR__, 2) . '/public/downloads';
    }

    public function windowsApp(): void
    {
        $this->sendFile(
            self::WINDOWS_SETUP,
            'application/octet-stream',
            'Windows installer not built yet. Run scripts/build-desktop-windows.ps1'
        );
    }

    public function linuxApp(): void
    {
        $this->sendFile(
            self::LINUX_APPIMAGE,
            'application/octet-stream',
            'Linux AppImage not built yet. Run scripts/build-desktop-linux.sh'
        );
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
