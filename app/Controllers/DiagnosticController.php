<?php

namespace App\Controllers;

use App\Services\DiagnosticService;

class DiagnosticController
{
    public function index(): string
    {
        $svc = new DiagnosticService();

        return view('diagnostic', [
            'title' => 'PC Lab Kit — Diagnostic Lab',
            'document_title' => 'PC Lab Kit — Diagnostic Lab',
            'config' => $svc->getConfig(),
        ]);
    }
}
