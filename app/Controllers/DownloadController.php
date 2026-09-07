<?php

declare(strict_types=1);

namespace App\Controllers;

/**
 * Serves installable desktop apps and probe agent bundles.
 */
class DownloadController
{
    private const WINDOWS_SETUP = 'PcLabKit-Setup-Windows-x64.exe';

    private const LINUX_APPIMAGE = 'PcLabKit-Linux-x64.AppImage';

    private const PROBE_ZIP = 'pc-lab-kit-probe-windows.zip';

    private const PROBE_LINUX_ZIP = 'pc-lab-kit-probe-linux.zip';

    private function downloadsRoot(): string
    {
        return dirname(__DIR__, 2) . '/public/downloads';
    }

    private function repoRoot(): string
    {
        return dirname(__DIR__, 2);
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

    /**
     * Stream the Linux probe agent (prebuilt zip if present, else zip agent/pclab_probe_linux on the fly).
     */
    public function probeLinux(): void
    {
        $prebuilt = $this->downloadsRoot() . '/' . self::PROBE_LINUX_ZIP;
        if (is_file($prebuilt)) {
            $this->sendAbsoluteFile($prebuilt, 'application/zip', self::PROBE_LINUX_ZIP);

            return;
        }

        $src = $this->repoRoot() . '/agent/pclab_probe_linux';
        if (!is_dir($src)) {
            http_response_code(404);
            header('Content-Type: text/plain; charset=utf-8');
            echo 'Linux probe source missing at agent/pclab_probe_linux';

            exit;
        }

        if (!class_exists(\ZipArchive::class)) {
            http_response_code(500);
            header('Content-Type: text/plain; charset=utf-8');
            echo 'ZipArchive extension required to package Linux probe';

            exit;
        }

        $tmp = tempnam(sys_get_temp_dir(), 'pclab-linux-probe-');
        if ($tmp === false) {
            http_response_code(500);
            header('Content-Type: text/plain; charset=utf-8');
            echo 'Could not create temp file for Linux probe zip';

            exit;
        }
        $zipPath = $tmp . '.zip';
        @unlink($tmp);

        $zip = new \ZipArchive();
        if ($zip->open($zipPath, \ZipArchive::CREATE | \ZipArchive::OVERWRITE) !== true) {
            http_response_code(500);
            header('Content-Type: text/plain; charset=utf-8');
            echo 'Could not create Linux probe zip';

            exit;
        }

        $srcLen = strlen($src) + 1;
        $iterator = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($src, \FilesystemIterator::SKIP_DOTS)
        );
        foreach ($iterator as $file) {
            /** @var \SplFileInfo $file */
            if (!$file->isFile()) {
                continue;
            }
            $full = $file->getPathname();
            $local = 'pclab_probe_linux/' . str_replace('\\', '/', substr($full, $srcLen));
            $zip->addFile($full, $local);
        }
        $zip->close();

        $this->sendAbsoluteFile($zipPath, 'application/zip', self::PROBE_LINUX_ZIP);
        @unlink($zipPath);
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

        $this->sendAbsoluteFile($path, $contentType, $filename);
    }

    private function sendAbsoluteFile(string $path, string $contentType, string $downloadName): void
    {
        header('Content-Type: ' . $contentType);
        header('Content-Disposition: attachment; filename="' . $downloadName . '"');
        header('Content-Length: ' . (string) filesize($path));
        readfile($path);
        exit;
    }
}
