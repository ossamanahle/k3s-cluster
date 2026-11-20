{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/a033e66ab94a6bedf2c3d58d93a36319d3cbbbaf";

  outputs = { nixpkgs, ... }:
  let
    systems = [ "x86_64-linux" ];
    forAllSystems = f:
      nixpkgs.lib.genAttrs systems (system:
        f nixpkgs.legacyPackages.${system});

    User = "1000:100";
  in {
    packages = forAllSystems (pkgs: 
    let
      base = with pkgs; [
        coreutils git neovim bat atuin tmux starship stow openssh man tldr curl
        ncurses procps ghostty.terminfo gnugrep
      ];

      zshPkgs = with pkgs; [ zsh zsh-autosuggestions zsh-syntax-highlighting ];

      users = pkgs.dockerTools.fakeNss.override {
        extraPasswdLines = [ "dev:x:1000:100:dev:/home/dev:/bin/zsh" ];
        extraGroupLines = [ "users:x:100:" ];
      };

      entryPoint = pkgs.writeShellScript "entrypoint" ''
        umask 022

        if [ ! -d "$HOME/dotfiles/.git" ]; then
          git clone https://github.com/ossamanahle/dotfiles.git "$HOME/dotfiles" \
           || echo "dotfiles clone failed..." >&2
        fi
        if [ -d "$HOME/dotfiles/" ]; then
          stow --no-folding -R -d "$HOME/dotfiles" -t "$HOME" $DOTFILES_PKGS \
           || echo "stow failed..." >&2
        fi

        mkdir -p "$HOME/.local/share/tailscale"
        tailscaled --tun=userspace-networking \
          --socks5-server=localhost:1055 \
          --statedir="$HOME/.local/share/tailscale" \
          > /tmp/tailscaled.log 2>&1 &

        exec "$@"
      '';

      zshrc = pkgs.writeTextDir "etc/zshrc" ''
        umask 022
        source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
        source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
      '';
  in {
    base = pkgs.dockerTools.buildLayeredImage {
      name = "dev-container";
      tag = "v1";

      enableFakechroot = true;
      fakeRootCommands = ''
        mkdir -p /workspaces /home/dev /tmp /var/run/tailscale
        chown 1000:100 /workspaces /home/dev /var/run/tailscale
        chmod 1777 /tmp
      '';

      config = {
        User = "${User}";

        Cmd = [ "/bin/zsh" ];

        EntryPoint = [ "${entryPoint}" ];
         
        Env = [
          "HOME=/home/dev"
          "USER=dev"
          "SHELL=/bin/zsh"
          "PATH=/bin"
          "DOTFILES_PKGS=zsh tmux git starship bat atuin nvim"
          "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
          "TERMINFO_DIRS=/share/terminfo"
          "KUBECONFIG=/home/dev/.kube/config"
          "SSH_AUTH_SOCK=/ssh-agent"
        ];
      };

      contents = base ++ zshPkgs ++ [ users zshrc ] ++ (with pkgs; [
        kubectl helmfile fluxcd tailscale kustomize sops age jq
        dockerTools.caCertificates dockerTools.binSh
      ]);
    };
    });
  };
}
