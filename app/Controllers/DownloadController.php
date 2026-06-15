<?php

namespace App\Controllers;

class DownloadController
{
    private const WINDOWS_FILE = 'PCVerse-Setup-Windows-x64.exe';
    private const LINUX_FILE = 'PCVerse-Setup-Linux-x64.run';

    private function downloadsRoot(): string
    {
        return dirname(__DIR__, 2) . '/public/downloads';
    }

    public function index(): string
    {
        return view('pages/download_hub', [
            'title' => 'Download PCVerse',
            'meta_description' => 'One click — Windows or Linux installer with everything you need.',
            'windows_ready' => $this->isReady('windows'),
            'linux_ready' => $this->isReady('linux'),
            'windows_url' => '/download/pcverse-windows-x64',
            'linux_url' => '/download/pcverse-linux-x64',
            'suggested_platform' => $this->suggestedPlatform(),
        ]);
    }

    /** @deprecated Redirect to hub — single download flow */
    public function windows(): never
    {
        header('Location: /download', true, 302);
        exit;
    }

    /** @deprecated Redirect to hub */
    public function linuxMac(): never
    {
        header('Location: /download', true, 302);
        exit;
    }

    public function windowsInstaller(): void
    {
        $this->sendFile(self::WINDOWS_FILE, 'application/octet-stream');
    }

    public function linuxInstaller(): void
    {
        $this->sendFile(self::LINUX_FILE, 'application/octet-stream');
    }

    private function isReady(string $platform): bool
    {
        $file = $platform === 'windows' ? self::WINDOWS_FILE : self::LINUX_FILE;

        return is_file($this->downloadsRoot() . '/' . $file);
    }

    private function suggestedPlatform(): ?string
    {
        $ua = strtolower((string) ($_SERVER['HTTP_USER_AGENT'] ?? ''));
        if ($ua === '') {
            return null;
        }
        if (str_contains($ua, 'windows')) {
            return 'windows';
        }
        if (str_contains($ua, 'linux')) {
            return 'linux';
        }

        return null;
    }

    private function sendFile(string $filename, string $contentType): void
    {
        $path = $this->downloadsRoot() . '/' . $filename;
        if (!is_file($path)) {
            http_response_code(404);
            header('Content-Type: text/plain; charset=utf-8');
            echo "Installer not built yet. Run scripts/build-installer-windows.ps1 or scripts/build-installer-linux.sh";

            exit;
        }

        header('Content-Type: ' . $contentType);
        header('Content-Disposition: attachment; filename="' . $filename . '"');
        header('Content-Length: ' . (string) filesize($path));
        readfile($path);
        exit;
    }
}
