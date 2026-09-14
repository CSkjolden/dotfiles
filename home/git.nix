{ pkgs, lib, ... }:
{
  programs.gh.enable = true;

  programs.git = {
    enable = true;
    lfs.enable = true;

    includes = [ { path = "~/.gitconfig.local"; } ];

    settings = {
      core.editor = "code --wait";
      core.pager = "less -FRX";
      init.defaultBranch = "main";
      pull.rebase = false;
      fetch.prune = true;
      push.autoSetupRemote = true;
      rerere.enabled = true;
    };
  };

  # Adds git identity from the logged-in GitHub session into ~/.gitconfig.local
  home.activation.gitIdentity = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    gitIdentity() {
      local gh_bin="${pkgs.gh}/bin/gh"
      "$gh_bin" auth status --hostname github.com >/dev/null 2>&1 || {
        echo "gitIdentity: not logged into gh - run 'just github-login' once, then 'just sync' again to set ~/.gitconfig.local" >&2
        return 0
      }

      local git_name git_email
      git_name="$("$gh_bin" api user --jq '.name // .login // empty' 2>/dev/null)" || git_name=""
      git_email="$("$gh_bin" api user/emails --jq 'map(select(.primary and .verified)) | .[0].email // empty' 2>/dev/null)" || git_email=""
      [[ -n "$git_name" && -n "$git_email" ]] || return 0

      $DRY_RUN_CMD ${pkgs.git}/bin/git config --file "$HOME/.gitconfig.local" user.name "$git_name"
      $DRY_RUN_CMD ${pkgs.git}/bin/git config --file "$HOME/.gitconfig.local" user.email "$git_email"
    }
    gitIdentity || true
  '';
}
