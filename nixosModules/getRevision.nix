{ pkgs, ... }:
let
  jsonFile = builtins.toJSON {
    url =
      if builtins.pathExists ./.git then
        builtins.readFile (
          pkgs.runCommand "getRemoteUrl" { buildInputs = [ pkgs.git ]; } ''
            grep -oP '(?<=url = ).*' ${./.git/config} | tr -d '\n' > $out;
          ''
        )
      else
        {
          url = "unknown";
        };
    branch =
      if builtins.pathExists ./.git then
        builtins.readFile (
          pkgs.runCommand "getBranch" { buildInputs = [ pkgs.git ]; } ''
            cat ${./.git/HEAD} | awk '{print $2}' | tr -d '\n' > $out;
          ''
        )
      else
        { branch = "unknown"; };
    rev =
      if builtins.pathExists ./.git then
        let
          gitRepo = builtins.fetchGit ./.; # Fetch the Git repository
        in
        gitRepo.rev # Access the 'rev' attribute directly
      else
        {
          rev = "unknown"; # Default value when there's no .git directory
        }
        .rev;
    lastModifiedDate =
      if builtins.pathExists ./.git then
        let
          gitRepo = builtins.fetchGit ./.; # Fetch the Git repository
        in
        gitRepo.lastModifiedDate
      else
        {
          lastModifiedDate = "unknown";
        }
        .lastModifiedDate;
  };
in
{
  environment = {
    etc = {
      "nixos/version".source = pkgs.writeText "projectGit.json" jsonFile;
    };
  };
}
