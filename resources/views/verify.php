<?php
/** @var string $hash @var bool $valid @var array|null $session */
?>
<div class="container" style="max-width:640px;padding:48px 16px">
    <h1>Certificate verification</h1>
    <p class="muted fs-sm">PC Lab Kit Truth Protocol — local session attestation</p>
    <?php if ($valid && is_array($session)): ?>
        <p style="color:#3fb950;font-weight:600">Valid session hash</p>
        <dl class="dx-hwref__dl">
            <dt>Signed</dt><dd><?= e((string) ($session['signed_at'] ?? '')) ?></dd>
            <dt>Profile</dt><dd><?= e((string) ($session['profile'] ?? '')) ?></dd>
            <dt>Probe</dt><dd><?= e((string) ($session['probe_version'] ?? '')) ?></dd>
            <dt>Stability margin</dt><dd><?= e((string) ($session['stability_margin_pct'] ?? '—')) ?>%</dd>
        </dl>
        <p class="muted fs-xs">Hash: <code><?= e($hash) ?></code></p>
    <?php else: ?>
        <p style="color:#f85149">Hash not found or invalid</p>
        <p class="muted fs-sm">Import a <code>.pclab</code> session in Command Center or verify on the machine that issued the certificate.</p>
    <?php endif; ?>
    <p><a href="/diagnostic">← Back to lab</a></p>
</div>
