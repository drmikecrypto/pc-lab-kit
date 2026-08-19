<?php

declare(strict_types=1);

namespace App\Application;

use App\Controllers\DiagnosticApiController;
use App\Services\DiagnosticService;
use App\Services\LabSuiteService;

/** Orchestrates Full Lab suite start → finalize. */
final class RunFullLab
{
    public function __construct(
        private ?LabSuiteService $suite = null,
    ) {
        $this->suite = $suite ?? new LabSuiteService();
    }

    /** @param array<string, mixed> $input @return array<string, mixed> */
    public function start(array $input): array
    {
        $profile = (string) ($input['profile'] ?? 'standard');

        return $this->suite->start($profile, $input);
    }

    /** @return array<string, mixed> */
    public function status(string $jobId): array
    {
        return $this->suite->status($jobId);
    }
}

/** Wraps diagnostic finalize pipeline entry point. */
final class FinalizeDiagnostic
{
    public function __construct(
        private ?DiagnosticApiController $api = null,
    ) {
        $this->api = $api ?? new DiagnosticApiController();
    }

    /** @param array<string, mixed> $raw @param array<string, mixed> $analysis */
    public function handle(string $mode, array $raw, array $analysis): array
    {
        $ref = new \ReflectionClass($this->api);
        $m = $ref->getMethod('finalizeDiagnostic');
        $m->setAccessible(true);

        return $m->invoke($this->api, $mode, $raw, $analysis);
    }
}

/** Export .pclab session via LabSessionService. */
final class ExportSession
{
    /** @param array<string, mixed> $analysis @return array<string, mixed> */
    public function handle(array $analysis, array $meta = []): array
    {
        return (new \App\Services\LabSessionService())->export($analysis, $meta);
    }
}
