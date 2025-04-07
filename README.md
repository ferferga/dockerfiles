## gphotosdl

Google has put measures to detect `--headless` and remote DevTools connections, so logging
in and connecting through ``chrome://inspect`` in another browser is completely out of question.

Notes for my future self of how I logged in, so they might not be detailed.
I've done it in Debian 12 Bookworm:

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
docker run --rm --network host -e DISPLAY=unix:0.0 -v /tmp/.X11-unix:/tmp/.X11-unix -v ./docker:/home/gphotosdl/.config --entrypoint /bin/bash -it --privileged --cap-add=SYS_ADMIN --name gphotosdl ghcr.io/ferferga/gphotosdl
```

4. In another terminal, enter the container as root:

```bash
docker exec --user 0:0 -it gphotosdl /bin/bash
```

5. Inside the container's shell as root:

```bash
apt update && apt install -y xorg nano
## Remove --headless from the arguments with:
nano /usr/bin/chromium
```

6. Run ``gphotosdl -login`` in the shell of point 2 (the one with user `gphotosdl`).
The browser will popup automatically, if not seeing anything, debug with `gphotosdl -debug`
or by calling `chromium`.
Once troubleshooting is done, start all over (removing contents of `./docker` to ensure clear state)

7. Close the browser after logging and you're done. You can move that profile
wherever you need (making sure you mount it to `/home/gphotosdl/.config` inside the container)
