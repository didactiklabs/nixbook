# The configuration's toggles, discovered from the module system itself:
# every option set with a real `enable` option (declared, bool, visible, not
# internal — renamed and removed options are invisible aliases, so they are
# never read; nor are defaults computed from other options that nothing
# sets), anywhere in the options tree up to `depth` levels
# (services.openssh, services.desktopManager.plasma6,
# programs.niri). Only those `enable` values are read from
# the configuration.
#
#   (import ./toggles.nix { inherit lib; }) { inherit options config; scope = "nixos"; }
#   -> [ { path = "services.openssh"; scope; enabled = true; description = "…"; } … ]
{ lib }:
{
  options,
  config,
  scope,
  depth ? 3,
}:
let
  # "Whether to enable the OpenSSH daemon." -> "the OpenSSH daemon"
  describe =
    opt:
    let
      d = opt.description or null;
      text =
        if builtins.isString d then
          d
        else if builtins.isAttrs d then
          d.text or ""
        else
          "";
      # First sentence of the first paragraph, on one line.
      paragraph = lib.replaceStrings [ "\n" ] [ " " ] (lib.head (lib.splitString "\n\n" (lib.trim text)));
      sentence = lib.head (lib.splitString ". " paragraph);
      m = builtins.match "Whether to (enable )?(.*)" sentence;
      what = lib.removeSuffix "." (if m != null then lib.elemAt m 1 else sentence);
    in
    if lib.stringLength what > 160 then lib.substring 0 157 what + "…" else what;

  realEnable =
    opt:
    lib.isOption opt
    && (opt.visible or true) != false
    && !(opt.internal or false)
    && (opt.type.name or null) == "bool"
    # Safe to read: set by the configuration, or a literal default. A default
    # computed from other options (it has a defaultText) that nothing
    # overrides is skipped: in a module that is off it may not evaluate at
    # all (hardware.nvidia.gsp.enable reads the unset NVIDIA package).
    && ((opt.highestPrio or 1500) < 1500 || !(opt ? defaultText));

  walk =
    opts: cfg: prefix: level:
    lib.concatLists (
      lib.mapAttrsToList (
        name: o:
        let
          path = if prefix == "" then name else "${prefix}.${name}";
          sub = builtins.tryEval (builtins.isAttrs o && !(lib.isOption o) && !(lib.hasPrefix "_" name));
        in
        if !(sub.success && sub.value) then
          [ ]
        else if o ? enable && realEnable o.enable then
          let
            on = builtins.tryEval (cfg.${name}.enable or false);
          in
          lib.optional (on.success && builtins.isBool on.value) {
            inherit path scope;
            enabled = on.value;
            description = describe o.enable;
          }
        else if level > 1 then
          walk o (cfg.${name} or { }) path (level - 1)
        else
          [ ]
      ) opts
    );
in
walk options config "" depth
