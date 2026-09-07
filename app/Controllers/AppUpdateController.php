<?php

declare(strict_types=1);

namespace App\Controllers;

use App\Services\AppUpdateService;

class AppUpdateController
{
    public function check(): string
    {
        $force = isset($_GET['refresh']) && $_GET['refresh'] === '1';

        return json_response((new AppUpdateService())->check($force));
    }
}
