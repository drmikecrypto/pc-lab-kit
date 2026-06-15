<?php

declare(strict_types=1);

namespace App\Console\Commands;

use App\Services\DiagnosticGameCatalogService;
use App\Support\Log;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;

class DiagnosticGamesRefreshCommand extends Command
{
    protected function configure(): void
    {
        $this->setName('games:refresh')
            ->setDescription('Refresh diagnostic game catalog (Steam + awards + optional LLM gap-fill).')
            ->addOption('force', 'f', InputOption::VALUE_NONE, 'Force refresh even if not stale');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $force = (bool)$input->getOption('force');
        $output->writeln('<info>[*] Diagnostic games refresh...</info>');

        try {
            $svc = new DiagnosticGameCatalogService();
            $result = $force ? $svc->refresh(true) : $svc->refreshIfStale(true);
            $output->writeln(json_encode($result, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));
            Log::info('CLI games:refresh completed', ['force' => $force]);

            return Command::SUCCESS;
        } catch (\Throwable $e) {
            $output->writeln(sprintf('<error>[!] %s</error>', $e->getMessage()));
            Log::error('CLI games:refresh failed', ['error' => $e->getMessage()]);

            return Command::FAILURE;
        }
    }
}
