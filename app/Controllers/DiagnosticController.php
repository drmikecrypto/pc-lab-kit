<?php

namespace App\Controllers;

use App\Services\DiagnosticService;

class DiagnosticController
{
    public function index(): string
    {
        $svc = new DiagnosticService();

        return view('diagnostic', [
            'title' => 'PCVerse — Diagnostic Lab',
            'document_title' => 'PCVerse — Diagnostic Lab',
            'config' => $svc->getConfig(),
        ]);
    }
}
