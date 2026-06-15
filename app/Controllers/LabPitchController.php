<?php

declare(strict_types=1);

namespace App\Controllers;

class LabPitchController
{
    public function pcTest(): string
    {
        return $this->renderPitch([
            'slug' => 'pc-test',
            'theme' => 'cyan',
            'title' => 'PC testing — PCVerse',
            'meta_description' => 'Real hardware health, bottlenecks, game performance, and safe auto-tuning — locally on your Windows PC.',
            'heading' => 'Know your system before your next upgrade',
            'lead' => 'PCVerse runs on the machine you use every day. No browser guesswork — real sensors, one clear report.',
            'benefits' => [
                'Hardware health under load: temps, power draw, and stability from real probes.',
                'Clear bottleneck mapping — see what limits you before spending money.',
                'Game performance and frametime guidance for titles you care about.',
                'Conservative auto-tuning after a deep scan — reversible OS/GPU tweaks only.',
                'Optional AI advisor (your API key) for personalized upgrade suggestions.',
                'Reports you can keep, share with a tech friend, or attach to a sale listing.',
            ],
            'primary_href' => '/download/pcverse-windows-x64',
            'primary_label' => 'Download for Windows',
            'secondary_href' => '/download/pcverse-linux-x64',
            'secondary_label' => 'Download for Linux',
            'sibling_href' => '/lab/rgb-sync',
            'sibling_label' => 'RGB & fan sync →',
        ]);
    }

    public function rgbSync(): string
    {
        return $this->renderPitch([
            'slug' => 'rgb-sync',
            'theme' => 'violet',
            'title' => 'RGB, fans & LCD — PCVerse',
            'meta_description' => 'Sync RAM, case lighting, fan curves, and pump LCD — locally via PCVerse Probe on Windows.',
            'heading' => 'Make your case yours',
            'lead' => 'Lighting, fans, and pump LCD should not live in five separate apps. PCVerse Probe handles them on your PC — no per-brand installer maze.',
            'benefits' => [
                'Control RAM, case, and strip lighting in one workflow.',
                'Pick colors, zones, and effects — not factory-only presets.',
                'Set fan curves alongside lighting — quiet when idle, cool under load.',
                'Pump and case LCD in the same flow — GIF files never leave your PC.',
                'OpenRGB portable bundled with Probe — run locally and stay in control.',
            ],
            'closing' => 'Windows desktop on your desk — everything runs locally.',
            'primary_href' => '/download/pcverse-linux-x64',
            'primary_label' => 'Download for Linux',
            'secondary_href' => '/download/pcverse-windows-x64',
            'secondary_label' => 'Download for Windows',
            'sibling_href' => '/lab/pc-test',
            'sibling_label' => 'PC testing →',
        ]);
    }

    /** @param array<string, mixed> $data */
    private function renderPitch(array $data): string
    {
        return view('lab/pitch', array_merge($data, [
            'document_title' => $data['heading'],
            'footer_minimal' => true,
        ]));
    }
}
