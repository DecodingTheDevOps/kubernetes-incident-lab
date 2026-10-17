# Windows setup (WSL2)

The lab runs on Bash, so on Windows you run it inside **WSL2** (Windows Subsystem for Linux) with Ubuntu, and let **Docker Desktop** provide Docker. You do everything in an Ubuntu terminal and never run PowerShell scripts, so there are no script-permission prompts. Plan for 20 to 30 minutes the first time, and one restart.

**You need:** Windows 10 (version 2004 or later) or Windows 11, 8 GB of RAM or more (16 GB is comfortable), about 15 GB of free disk space, virtualisation switched on in your BIOS (usually already on), and administrator rights for the installs.

## 1. Install WSL2 and Ubuntu
Open **PowerShell as Administrator** (Start menu, type PowerShell, right-click, Run as administrator) and run:

```powershell
wsl --install
```

On most PCs this turns WSL on and installs Ubuntu. Restart when asked. After the restart an Ubuntu window opens and asks you to create a Linux username and password. Remember them: `sudo` will ask for that password later.

If WSL was already there without a distro, run `wsl --install -d Ubuntu`. Check that it is version 2 with `wsl -l -v` (the VERSION column should say 2).

## 2. Install Docker Desktop
Download it from docker.com, or run `winget install Docker.DockerDesktop`. Start Docker Desktop, accept the terms, and choose the **WSL 2** option if it asks.

## 3. Connect Docker Desktop to Ubuntu
In Docker Desktop, open **Settings** (the gear):
1. **General**: tick **Use the WSL 2 based engine**.
2. **Resources**, then **WSL integration**: switch **Ubuntu** on.
3. Click **Apply & restart**.

## 4. Open an Ubuntu terminal
Type `wsl` in Command Prompt or PowerShell, or open **Ubuntu** from the Start menu. Everything from here on happens in that Ubuntu terminal. Check Docker is reachable:

```bash
docker version
```

You should see both a Client and a Server section. If the Server part is missing, see Troubleshooting below.

## 5. Install kubectl and kind inside Ubuntu
These are not part of Docker Desktop. Check what you already have first:

```bash
kubectl version --client
kind version
```

If a command is "not found", install it. kind is available through `apt` on some Ubuntu releases and not on others, so try that first:

```bash
sudo apt update
sudo apt install -y kind        # if it says "Unable to locate package", use the download below
```

If `apt` does not have it, download the binary (use `kind-linux-arm64` instead of `kind-linux-amd64` if `uname -m` prints aarch64):

```bash
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.18.0/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind
```

kubectl:

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

Then check both again with `kubectl version --client` and `kind version`.

## 6. Optional: log in to Docker Hub
Setup downloads six small images once. Docker Hub limits anonymous downloads, and on a shared or busy network you may hit "toomanyrequests" or "rate limit" errors. A free Docker Hub account avoids this:

```bash
docker login
```

Follow the prompts. After setup finishes, the images are inside the cluster and the lab works offline.

## 7. Put the lab in the Linux home folder
Files under `/mnt/c/...` (your Windows drives) are slow and can lose their permissions. Copy the zip into your Linux home folder and unzip it there. Replace `YourName` and the file name with yours:

```bash
sudo apt update && sudo apt install -y unzip
cp /mnt/c/Users/YourName/Downloads/K8s-Incident-Lab-*.zip ~/
cd ~
unzip K8s-Incident-Lab-*.zip
cd K8s-Incident-Lab-*/
```

## 8. Run the lab
```bash
./lab.sh doctor     # checks Docker, kubectl, kind and memory
./lab.sh setup      # creates the local cluster (2 to 4 minutes, once)
./lab.sh list
./lab.sh start 1
```

If `./lab.sh` says "permission denied", run it as `bash ./lab.sh doctor`, or give it permission once with `chmod +x lab.sh`.

## Work in your IDE
With **VS Code**, install the **WSL** extension, then in the Ubuntu terminal run `code .` inside the lab folder. VS Code opens connected to Ubuntu, and its built-in terminal is the Ubuntu shell, so you can read the scenario and run commands side by side.

## Give Docker enough memory
The lab's cluster needs about 4 to 6 GB. By default WSL can use half of your RAM. To set it explicitly, create or edit the file `C:\Users\YourName\.wslconfig` with:

```
[wsl2]
memory=6GB
```

Then run `wsl --shutdown` in PowerShell and start Docker Desktop again.

## Troubleshooting
| Problem | Likely cause | Fix |
| --- | --- | --- |
| `wsl --install` only prints help text | WSL is already installed, or Windows is old | Run `wsl --install -d Ubuntu`; on Windows 10 make sure updates are installed |
| "Virtualization is disabled" or WSL 2 will not start | Virtualisation is off in the BIOS | Turn on Intel VT-x / AMD-V (SVM) in the BIOS, then retry |
| `docker: command not found` in Ubuntu | WSL integration is off | Docker Desktop, Settings, Resources, WSL integration: switch Ubuntu on, Apply & restart |
| "Cannot connect to the Docker daemon" | Docker Desktop is not running | Start Docker Desktop and wait until it says it is running |
| `doctor` warns about low memory | Docker or WSL has too little memory | Use the `.wslconfig` step above |
| "toomanyrequests" or "rate limit" during setup | Docker Hub anonymous limit | `docker login`, then run `./lab.sh setup` again |
| Setup is very slow | The lab folder is under `/mnt/c` | Copy it to your Linux home folder (step 7) |
| `kind: command not found` | kind was not installed in Ubuntu | Repeat step 5 inside the Ubuntu terminal, not PowerShell |

Still stuck? Run `./lab.sh doctor` and open an issue in this repository with its output.
