## gphotosdl

Google has put measures to detect `--headless` and remote DevTools connections, so logging
in and connecting through ``chrome://inspect`` in another browser is completely out of question.

Notes for my future self of how I logged in, so they might not be detailed.

### Setting up through Debian
*I've done it in Debian 12 Bookworm*

1. Allow external X11 connections:

```bash
xhost +
```

2. Create a folder for storing the session data:

```bash
mkdir docker
chown 101:102 -R docker
```

3. Run the container like this (where `./docker` is where the data is going to be stored):

```bash
docker run --rm --network host -e DISPLAY=unix:0.0 -v /tmp/.X11-unix:/tmp/.X11-unix -v ./docker:/home/gphotosdl/gphotosdl --entrypoint /bin/bash -it --privileged --name gphotosdl ghcr.io/ferferga/gphotosdl
```

4. In another terminal, enter the container as root:

```bash
docker exec --user 0:0 -it gphotosdl /bin/bash
```

5. Inside the container's shell as root:

```bash
install_packages xorg nano
## Remove --headless from the arguments with:
nano /usr/bin/chromium
```

6. Run ``gphotosdl -login`` in the shell of point 2 (the one with user `gphotosdl`).
The browser will popup automatically, if not seeing anything, debug with `gphotosdl -debug`
or by calling `chromium`.
Once troubleshooting is done, start all over (removing contents of `./docker` to ensure clear state)

7. After logging, make sure that in Brave Browser settings you:
    - Set the startup page to "New Tab" or any other setting instead of "Continue where I left off".
    - Clear all data on browser exit except cookies
    - Disable "Keep apps running after closing" 

8. Close the browser after logging and you're done. You can move that profile
wherever you need (making sure you mount it to `/home/gphotosdl/gphotosdl` inside the container)

### Setting up through Windows

I run this in a headless Raspberry Pi, so this still assumes a Debian environment, but the display part is done in Windows.

1. Do steps 2-4 with the following particularities:
    - In 3, skip the `-v /tmp/.X11-unix:/tmp/.X11-unix` argument
    - In 5, install as well `ssh` and run the following commands:
    ```
    # Set the password you wish, we will use it later
    passwd gphotosdl
    # Change the port to any free port. Ensure X11Forwarding is set to yes
    nano /etc/ssh/sshd_config
    # Ensure shell of gphotosdl user is /bin/bash, not /bin/false
    nano /etc/passwd
    # Necessary for ssh daemon
    mkdir -p /run/sshd
    # After all of that, start ssh daemon
    /usr/sbin/sshd -D
    ```
2. In Windows, download [Portable X-Server](https://github.com/P-St/Portable-X-Server/releases) and [Putty](https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html)
3. Open VcXsrv (from Portable X-Server). If prompted, allow firewall or even disable it temporarily (only do this if you're behind a router firewall or NAT)
4. Open Putty, input the IP of the Raspberry Pi with the port you added to `/etc/ssh/sshd_config`. In `Connection > SSH > X11`, tick `Enable X11 Forwarding` with
`127.0.0.1:0.0` location.
5. Start the connection on Putty, logging in as `gphotosdl` user with password used in step 2.

From now on, the process is exactly the same as the [Debian's counterpart](#setting-up-through-debian). 