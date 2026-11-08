// Actualizador independiente de AniMaple.
//
// Se lanza desde la aplicación con:
//   animaple_updater.exe --pid <pid> --stage <dir> --target <dir> --exe <ruta> [--log <ruta>]
//
// Espera el cierre de la aplicación, reemplaza los archivos con una barra de
// progreso visible, relanza la aplicación y se cierra solo.
//
// Compilar con el compilador de .NET Framework incluido en Windows:
//   csc.exe /target:winexe /out:animaple_updater.exe updater\AniMapleUpdater.cs

using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Windows.Forms;

namespace AniMapleUpdater
{
    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            Options options = Options.Parse(args);
            if (options == null)
            {
                MessageBox.Show(
                    "Uso: animaple_updater.exe --pid N --stage DIR --target DIR --exe RUTA [--log RUTA]",
                    "AniMaple Updater",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return;
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new UpdateForm(options));
        }
    }

    internal sealed class Options
    {
        public int Pid;
        public string Stage;
        public string Target;
        public string Exe;
        public string Log;

        public static Options Parse(string[] args)
        {
            Options o = new Options();
            for (int i = 0; i < args.Length - 1; i++)
            {
                switch (args[i])
                {
                    case "--pid":
                        int.TryParse(args[i + 1], out o.Pid);
                        i++;
                        break;
                    case "--stage":
                        o.Stage = args[i + 1];
                        i++;
                        break;
                    case "--target":
                        o.Target = args[i + 1];
                        i++;
                        break;
                    case "--exe":
                        o.Exe = args[i + 1];
                        i++;
                        break;
                    case "--log":
                        o.Log = args[i + 1];
                        i++;
                        break;
                }
            }

            if (string.IsNullOrEmpty(o.Stage) || string.IsNullOrEmpty(o.Target) || string.IsNullOrEmpty(o.Exe))
            {
                return null;
            }

            if (string.IsNullOrEmpty(o.Log))
            {
                o.Log = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "AniMaple",
                    "update.log");
            }

            return o;
        }
    }

    internal sealed class UpdateForm : Form
    {
        private readonly Options _options;
        private readonly Label _status;
        private readonly Panel _track;
        private readonly Panel _fill;
        private readonly System.Windows.Forms.Timer _timer;

        private Thread _worker;
        private volatile bool _finished;
        private volatile string _statusText;
        private volatile int _percent;

        public UpdateForm(Options options)
        {
            _options = options;
            _statusText = "Esperando el cierre de la aplicación...";
            _percent = 0;

            Text = "AniMaple";
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.CenterScreen;
            TopMost = true;
            ShowInTaskbar = true;
            ClientSize = new Size(500, 168);
            BackColor = Color.FromArgb(16, 16, 24);
            ForeColor = Color.FromArgb(243, 244, 246);
            Font = new Font("Segoe UI", 9.5f);
            DoubleBuffered = true;

            Label title = new Label();
            title.Text = "Actualizando AniMaple";
            title.Font = new Font("Segoe UI Semibold", 12f, FontStyle.Bold);
            title.ForeColor = Color.FromArgb(243, 244, 246);
            title.AutoSize = false;
            title.SetBounds(28, 26, 444, 26);
            Controls.Add(title);

            _status = new Label();
            _status.Text = _statusText;
            _status.Font = new Font("Segoe UI", 9f);
            _status.ForeColor = Color.FromArgb(156, 163, 175);
            _status.AutoSize = false;
            _status.SetBounds(28, 60, 444, 22);
            Controls.Add(_status);

            _track = new Panel();
            _track.SetBounds(28, 96, 444, 8);
            _track.BackColor = Color.FromArgb(38, 38, 52);
            Controls.Add(_track);

            _fill = new Panel();
            _fill.SetBounds(0, 0, 0, 8);
            _fill.BackColor = Color.FromArgb(139, 92, 246);
            _track.Controls.Add(_fill);

            Label hint = new Label();
            hint.Text = "No cierres esta ventana. La aplicación se abrirá al terminar.";
            hint.Font = new Font("Segoe UI", 8.5f);
            hint.ForeColor = Color.FromArgb(107, 114, 128);
            hint.AutoSize = false;
            hint.SetBounds(28, 120, 444, 20);
            Controls.Add(hint);

            _timer = new System.Windows.Forms.Timer();
            _timer.Interval = 120;
            _timer.Tick += OnTick;
            _timer.Start();

            Shown += OnShown;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            using (Pen pen = new Pen(Color.FromArgb(52, 52, 70), 1))
            {
                e.Graphics.DrawRectangle(pen, 0, 0, Width - 1, Height - 1);
            }
        }

        private void OnShown(object sender, EventArgs e)
        {
            _worker = new Thread(Run);
            _worker.IsBackground = true;
            _worker.Start();
        }

        private void OnTick(object sender, EventArgs e)
        {
            _status.Text = _statusText;

            int width = (int)(_track.Width * (_percent / 100.0));
            if (width < 0) width = 0;
            if (width > _track.Width) width = _track.Width;
            _fill.Width = width;

            if (_finished)
            {
                _timer.Stop();
                Close();
            }
        }

        private void Run()
        {
            try
            {
                Log("Actualizacion iniciada");
                WaitForExit();
                CopyFiles();
                Log("Archivos copiados");
                Relaunch();
                Log("Actualizacion completada");
                _statusText = "Listo. Abriendo la aplicación...";
                _percent = 100;
                Thread.Sleep(600);
                _finished = true;
            }
            catch (Exception ex)
            {
                Log("ERROR: " + ex.Message);
                _statusText = "No se pudo completar la actualización.";
                try
                {
                    Relaunch();
                }
                catch
                {
                }
                Thread.Sleep(2500);
                _finished = true;
            }
        }

        private void WaitForExit()
        {
            if (_options.Pid <= 0) return;

            try
            {
                Process process = Process.GetProcessById(_options.Pid);
                _statusText = "Cerrando la aplicación...";
                // La aplicación debe cerrarse sola en menos de un segundo. Si
                // no lo hace, se fuerza el cierre sin hacer esperar al usuario.
                if (!process.WaitForExit(8000))
                {
                    Log("El proceso no cerró, terminándolo");
                    process.Kill();
                    process.WaitForExit(5000);
                }
            }
            catch (ArgumentException)
            {
                // El proceso ya no existe.
            }

            Thread.Sleep(700);
        }

        private void CopyFiles()
        {
            string stage = _options.Stage;
            string target = _options.Target;

            if (!Directory.Exists(stage))
            {
                throw new DirectoryNotFoundException("No existe el directorio de la actualización: " + stage);
            }

            string[] files = Directory.GetFiles(stage, "*", SearchOption.AllDirectories);
            long total = 0;
            for (int i = 0; i < files.Length; i++)
            {
                total += new FileInfo(files[i]).Length;
            }
            if (total <= 0) total = 1;

            string self = Path.GetFullPath(Application.ExecutablePath);
            long copied = 0;

            for (int i = 0; i < files.Length; i++)
            {
                string source = files[i];
                string relative = source.Substring(stage.Length).TrimStart('\\', '/');
                string destination = Path.Combine(target, relative);

                // No se puede sobrescribir el ejecutable que está en marcha.
                if (string.Equals(Path.GetFullPath(destination), self, StringComparison.OrdinalIgnoreCase))
                {
                    copied += new FileInfo(source).Length;
                    continue;
                }

                string directory = Path.GetDirectoryName(destination);
                if (!string.IsNullOrEmpty(directory))
                {
                    Directory.CreateDirectory(directory);
                }

                CopyWithRetry(source, destination);

                copied += new FileInfo(source).Length;
                _percent = (int)(copied * 100 / total);
                _statusText = "Reemplazando archivos... " + _percent + "%";
            }
        }

        private static void CopyWithRetry(string source, string destination)
        {
            int attempts = 0;
            while (true)
            {
                try
                {
                    File.Copy(source, destination, true);
                    return;
                }
                catch (IOException)
                {
                    attempts++;
                    if (attempts >= 6) throw;
                    Thread.Sleep(400);
                }
                catch (UnauthorizedAccessException)
                {
                    attempts++;
                    if (attempts >= 6) throw;
                    Thread.Sleep(400);
                }
            }
        }

        private void Relaunch()
        {
            ProcessStartInfo info = new ProcessStartInfo();
            info.FileName = _options.Exe;
            info.WorkingDirectory = _options.Target;
            info.UseShellExecute = true;
            Process.Start(info);
        }

        private void Log(string message)
        {
            try
            {
                string directory = Path.GetDirectoryName(_options.Log);
                if (!string.IsNullOrEmpty(directory))
                {
                    Directory.CreateDirectory(directory);
                }
                File.AppendAllText(
                    _options.Log,
                    "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "] " + message + Environment.NewLine);
            }
            catch
            {
            }
        }
    }
}
