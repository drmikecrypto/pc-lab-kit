using System.Diagnostics;
using System.IO.Compression;
using System.Reflection;

namespace PCVerse.Setup;

internal sealed class SetupForm : Form
{
    private readonly TextBox _folderBox;
    private readonly CheckBox _desktopShortcut;
    private readonly CheckBox _launchAfter;
    private readonly Button _installBtn;
    private readonly Button _browseBtn;
    private readonly ProgressBar _progress;
    private readonly Label _status;

    public SetupForm()
    {
        Text = "PCVerse Setup";
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ClientSize = new Size(560, 380);
        BackColor = Color.FromArgb(13, 17, 23);
        ForeColor = Color.White;

        var title = new Label
        {
            Text = "PCVerse",
            Font = new Font("Segoe UI", 22F, FontStyle.Bold),
            AutoSize = true,
            Location = new Point(32, 24),
            ForeColor = Color.FromArgb(34, 211, 238),
        };

        var subtitle = new Label
        {
            Text = "Install the complete local PC lab — web UI, diagnostics, and PCVerse Probe.",
            Font = new Font("Segoe UI", 10F),
            Location = new Point(34, 68),
            Size = new Size(490, 44),
            ForeColor = Color.FromArgb(180, 190, 200),
        };

        var folderLabel = new Label
        {
            Text = "Install folder",
            Font = new Font("Segoe UI Semibold", 9.5F, FontStyle.Bold),
            AutoSize = true,
            Location = new Point(34, 128),
        };

        _folderBox = new TextBox
        {
            Location = new Point(34, 152),
            Size = new Size(390, 28),
            BackColor = Color.FromArgb(22, 27, 34),
            ForeColor = Color.White,
            BorderStyle = BorderStyle.FixedSingle,
            Text = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PCVerse"),
        };

        _browseBtn = new Button
        {
            Text = "Browse…",
            Location = new Point(432, 150),
            Size = new Size(96, 30),
            FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(33, 38, 45),
            ForeColor = Color.White,
            Cursor = Cursors.Hand,
        };
        _browseBtn.FlatAppearance.BorderColor = Color.FromArgb(60, 68, 78);
        _browseBtn.Click += (_, _) => BrowseFolder();

        _desktopShortcut = new CheckBox
        {
            Text = "Create desktop shortcut",
            Location = new Point(36, 198),
            AutoSize = true,
            Checked = true,
            ForeColor = Color.FromArgb(210, 215, 220),
        };

        _launchAfter = new CheckBox
        {
            Text = "Launch PCVerse when setup finishes",
            Location = new Point(36, 226),
            AutoSize = true,
            Checked = true,
            ForeColor = Color.FromArgb(210, 215, 220),
        };

        _progress = new ProgressBar
        {
            Location = new Point(34, 268),
            Size = new Size(494, 18),
            Style = ProgressBarStyle.Continuous,
            Visible = false,
        };

        _status = new Label
        {
            Text = "Ready to install.",
            Location = new Point(34, 296),
            Size = new Size(494, 24),
            ForeColor = Color.FromArgb(150, 160, 170),
        };

        _installBtn = new Button
        {
            Text = "Install",
            Location = new Point(350, 328),
            Size = new Size(100, 34),
            FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(34, 211, 238),
            ForeColor = Color.FromArgb(13, 17, 23),
            Font = new Font("Segoe UI Semibold", 9.5F, FontStyle.Bold),
            Cursor = Cursors.Hand,
        };
        _installBtn.FlatAppearance.BorderSize = 0;
        _installBtn.Click += async (_, _) => await InstallAsync();

        var cancelBtn = new Button
        {
            Text = "Cancel",
            Location = new Point(460, 328),
            Size = new Size(68, 34),
            FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(33, 38, 45),
            ForeColor = Color.White,
            Cursor = Cursors.Hand,
        };
        cancelBtn.FlatAppearance.BorderColor = Color.FromArgb(60, 68, 78);
        cancelBtn.Click += (_, _) => Close();

        Controls.AddRange([
            title, subtitle, folderLabel, _folderBox, _browseBtn,
            _desktopShortcut, _launchAfter, _progress, _status, _installBtn, cancelBtn,
        ]);
    }

    private void BrowseFolder()
    {
        using var dialog = new FolderBrowserDialog
        {
            Description = "Choose where to install PCVerse",
            SelectedPath = _folderBox.Text,
            ShowNewFolderButton = true,
        };
        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            _folderBox.Text = dialog.SelectedPath;
        }
    }

    private async Task InstallAsync()
    {
        var target = _folderBox.Text.Trim();
        if (target.Length == 0)
        {
            MessageBox.Show(this, "Choose an install folder.", "PCVerse Setup", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        SetBusy(true);
        try
        {
            _status.Text = "Extracting files…";
            _progress.Value = 10;
            await Task.Run(() => ExtractPayload(target));

            _status.Text = "Finishing setup…";
            _progress.Value = 70;
            await Task.Run(() => PostInstall(target));

            if (_desktopShortcut.Checked)
            {
                _status.Text = "Creating shortcut…";
                _progress.Value = 90;
                CreateDesktopShortcut(target);
            }

            _progress.Value = 100;
            _status.Text = "Installation complete.";

            if (_launchAfter.Checked)
            {
                LaunchApp(target);
            }

            MessageBox.Show(
                this,
                "PCVerse is installed.\n\nOpen the lab at http://127.0.0.1:8080/diagnostic\n\nUse the desktop shortcut or PCVerse.bat in your install folder.",
                "PCVerse Setup",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
            Close();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "Installation failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
            _status.Text = "Installation failed.";
            _progress.Value = 0;
        }
        finally
        {
            SetBusy(false);
        }
    }

    private void SetBusy(bool busy)
    {
        _installBtn.Enabled = !busy;
        _browseBtn.Enabled = !busy;
        _folderBox.Enabled = !busy;
        _desktopShortcut.Enabled = !busy;
        _launchAfter.Enabled = !busy;
        _progress.Visible = busy;
        if (!busy)
        {
            _progress.Value = 0;
        }
    }

    private static void ExtractPayload(string target)
    {
        Directory.CreateDirectory(target);
        using var stream = OpenPayloadStream();
        using var archive = new ZipArchive(stream, ZipArchiveMode.Read);
        foreach (var entry in archive.Entries)
        {
            if (string.IsNullOrEmpty(entry.Name) && entry.FullName.EndsWith('/'))
            {
                Directory.CreateDirectory(Path.Combine(target, entry.FullName));
                continue;
            }

            var dest = Path.Combine(target, entry.FullName);
            var dir = Path.GetDirectoryName(dest);
            if (!string.IsNullOrEmpty(dir))
            {
                Directory.CreateDirectory(dir);
            }

            entry.ExtractToFile(dest, overwrite: true);
        }
    }

    private static Stream OpenPayloadStream()
    {
        var assembly = Assembly.GetExecutingAssembly();
        var resource = assembly.GetManifestResourceStream("PCVerse.Payload.zip");
        if (resource != null)
        {
            return resource;
        }

        var sidecar = Path.Combine(AppContext.BaseDirectory, "payload.zip");
        if (File.Exists(sidecar))
        {
            return File.OpenRead(sidecar);
        }

        throw new InvalidOperationException("Installer payload is missing. Rebuild with scripts/build-installer-windows.ps1");
    }

    private static void PostInstall(string target)
    {
        var envExample = Path.Combine(target, ".env.example");
        var envFile = Path.Combine(target, ".env");
        if (File.Exists(envExample) && !File.Exists(envFile))
        {
            File.Copy(envExample, envFile);
        }

        foreach (var sub in new[] { "storage/cache/benchmark", "storage/settings", "storage/database", "public/downloads" })
        {
            Directory.CreateDirectory(Path.Combine(target, sub));
        }

        var php = ResolvePhp(target);
        var migrate = Path.Combine(target, "bin", "migrate.php");
        if (File.Exists(migrate))
        {
            RunProcess(php, $"\"{migrate}\"", target);
        }
    }

    private static string ResolvePhp(string target)
    {
        var bundled = Path.Combine(target, "runtime", "php", "php.exe");
        if (File.Exists(bundled))
        {
            return bundled;
        }

        return "php";
    }

    private static void RunProcess(string file, string args, string workDir)
    {
        using var proc = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = file,
                Arguments = args,
                WorkingDirectory = workDir,
                UseShellExecute = false,
                CreateNoWindow = true,
            },
        };
        proc.Start();
        proc.WaitForExit(60000);
    }

    private static void CreateDesktopShortcut(string target)
    {
        var launcher = Path.Combine(target, "PCVerse.bat");
        if (!File.Exists(launcher))
        {
            return;
        }

        var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
        var linkPath = Path.Combine(desktop, "PCVerse.lnk");
        var type = Type.GetTypeFromProgID("WScript.Shell");
        if (type == null)
        {
            return;
        }

        dynamic shell = Activator.CreateInstance(type)!;
        dynamic shortcut = shell.CreateShortcut(linkPath);
        shortcut.TargetPath = launcher;
        shortcut.WorkingDirectory = target;
        shortcut.Description = "PCVerse — local PC lab";
        shortcut.Save();
    }

    private static void LaunchApp(string target)
    {
        var launcher = Path.Combine(target, "PCVerse.bat");
        if (!File.Exists(launcher))
        {
            return;
        }

        Process.Start(new ProcessStartInfo
        {
            FileName = launcher,
            WorkingDirectory = target,
            UseShellExecute = true,
        });
    }
}
