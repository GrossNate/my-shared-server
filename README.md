# my-shared-server

Setup instructions a config for my Dreamhost VPS. Individual sites/applications
will run in their own Docker Compose networks and be pulled from their own
repos.

> [!CAUTION]
> I set this up as a private repo. As cool as it would be to show off the
> thought that went into it, I don't necessarily want a public list of all the
> sites/applications I'm running on the server.

## Bootstrap server

I'm writing this myself and instructions are based on a Dreamhost Shared VPS.
They shouldn't vary too much on other servers, but there are a few things that
Dreamhost does by default (e.g. block all ports except 22, set up fail2ban
brute-force protection, automatic security upgrades to Ubuntu) that you might
need to handle on other servers.

### 1. First we need to give ourselves access to the repo.

On the VPS, generate a key (no passphrase) with . . .
 ```shell
 ssh-keygen -t ed25519 \
-f ~/.ssh/github-server-deploy \
-C "dreamhost-server-deploy"
```

And copy the public key from . . .
```shell
cat ~/.ssh/github-server-deploy.pub
```

Then in the GitHub private repo go to `Settings >  Deploy keys` and `Add
deploy key`.

Then add the SSH configuration entry . . .
```shell
cat >> ~/.ssh/config <<'EOF'
Host github-server
    HostName github.com
    User git
    IdentityFile ~/.ssh/github-server-deploy
    IdentitiesOnly yes
EOF

chmod 600 ~/.ssh/config
```

Test the connection . . .
```shell
ssh -T github-server
```

Clone the server repository . . .
```shell
sudo install -d -o "$USER" -g "$(id -gn)" /srv/server

git clone git@github-server:GrossNate/my-shared-server.git \
  /srv/server

cd /srv/server
```

Make `bootstrap.sh` executable and run it . . .
```shell
chmod +x bootstrap.sh
./bootstrap.sh
```