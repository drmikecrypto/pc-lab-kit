<?php
/** @var string $hash @var bool $valid @var array|null $session */
?>
<div class="container pclab-verify">
    <p class="pclab-verify__eyebrow">Truth Protocol</p>
    <h1 class="pclab-verify__title">Certificate verification</h1>
    <p class="muted fs-sm">Local session attestation — the hash is checked on this machine, not in the cloud.</p>
    <?php if ($valid && is_array($session)): ?>
        <article class="pclab-verify__card pclab-verify__card--ok">
            <p class="pclab-verify__status">Valid session hash</p>
            <dl class="dx-hwref__dl">
                <dt>Signed</dt><dd><?= e((string) ($session['signed_at'] ?? '')) ?></dd>
                <dt>Profile</dt><dd><?= e((string) ($session['profile'] ?? '')) ?></dd>
                <dt>Probe</dt><dd><?= e((string) ($session['probe_version'] ?? '')) ?></dd>
                <dt>Stability margin</dt><dd><?= e((string) ($session['stability_margin_pct'] ?? '—')) ?>%</dd>
            </dl>
            <p class="muted fs-xs">Hash: <code><?= e($hash) ?></code></p>
        </article>
    <?php else: ?>
        <article class="pclab-verify__card pclab-verify__card--bad">
            <p class="pclab-verify__status">Hash not found or invalid</p>
            <p class="muted fs-sm">Import a <code>.pclab</code> session in Command Center or verify on the machine that issued the certificate.</p>
            <p class="muted fs-xs">Hash: <code><?= e($hash) ?></code></p>
        </article>
    <?php endif; ?>
    <p class="pclab-verify__back"><a href="/diagnostic">Back to lab</a></p>
</div>
