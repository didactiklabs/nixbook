{ pkgs }:
# The faces the shell names in appearance.fonts that nixpkgs doesn't ship (or
# nothing installed): without them every label fell back to fontconfig's
# sans-serif. Installed by the Home Manager module and the greeter.
#   Google Sans Flex  main, title and numbers (variable: weight, width,
#                     optical size, roundness)
#   Space Grotesk     expressive: the desktop clock and date
#   Readex Pro        reading: the AI chat (nixpkgs)
#   Rajdhani          the Cyberpunk 2077 theme's condensed tech face
#                     (themes.json style.fonts; static weights)
#   Zen Maru Gothic   the Studio Ghibli theme's soft rounded face (main,
#                     numbers; static weights, with Japanese)
#   Klee One          ...and its hand-lettered storybook titles
# Google Sans Flex, Space Grotesk, Rajdhani, Zen Maru Gothic and Klee One come
# from google/fonts (SIL OFL 1.1).
let
  rev = "3dc14e61f108f036db84188b9b405a67df9b7c88"; # google/fonts
  ofl =
    dir: file: sha256: licenseSha256:
    let
      base = "https://raw.githubusercontent.com/google/fonts/${rev}/ofl/${dir}";
    in
    {
      font = pkgs.fetchurl {
        name = "${dir}.ttf";
        url = "${base}/${file}";
        inherit sha256;
      };
      license = pkgs.fetchurl {
        name = "${dir}-OFL.txt";
        url = "${base}/OFL.txt";
        sha256 = licenseSha256;
      };
    };
  googleSansFlex =
    ofl "googlesansflex" "GoogleSansFlex%5BGRAD%2CROND%2Copsz%2Cslnt%2Cwdth%2Cwght%5D.ttf"
      "1zmncn16zy24k9n9r6rcfggsl8w70wh4s4whd1zf1wnbpqplh6n3"
      "0dri0r8js9b1z5yfard0197l1bfqcca4sg9qdr5jhvg3cfgxc4zw";
  spaceGrotesk =
    ofl "spacegrotesk" "SpaceGrotesk%5Bwght%5D.ttf"
      "0wlzszxzq3wp6mjh7rv363m1lkzh3rskfh8z1xf6yhwkzkhnvbdc"
      "0whsssfn8pg0as6saz3fynlmban9lxjna046yaxybibiqdjyak2n";
  rajdhani = weight: sha256: ofl "rajdhani" "Rajdhani-${weight}.ttf" sha256 rajdhaniLicense;
  rajdhaniLicense = "07sxn6rz1yyyx979d5wp949qv2hf6nxf39imvmzd5hx1sdbz6bpn";
  rajdhaniWeights = {
    Medium = "1hpaj5jqvf4pdg18cnkzzaifczdmx9i1ffy5ba3y61n2wk7pvzqj";
    SemiBold = "1nimy9dq4w02l2fbx2xprw6qcazxx5ym6nmhzscmjrna31dd5fwl";
    Bold = "1zba4aii129c3bdcn5ajp90rh5wnazvhn3clfyb4x8c66bfp0539";
  };
  zenMaru = weight: sha256: ofl "zenmarugothic" "ZenMaruGothic-${weight}.ttf" sha256 zenMaruLicense;
  zenMaruLicense = "0gfbs0580mmgdwnhm0bwbxq5cxkx1ws5s2a9x7hqx7chw5ycy81a";
  zenMaruWeights = {
    Regular = "1vqi27hlrkhjy57nj80psdd4jl9x7y1rqqjy4bi3m6g08csvbh50";
    Medium = "0frb14idid1699sspcmrly08phwp784zasf7zhbxw7jp2f5bkz9w";
    Bold = "0idpkrnmkhwmr0zaam7k794z1k2fcz43b0ka2jh26mcbkiml497y";
  };
  klee = weight: sha256: ofl "kleeone" "KleeOne-${weight}.ttf" sha256 kleeLicense;
  kleeLicense = "0f6ac5qmbvm7fccrvbb9anbhf49s6fjz1dixaflla8waivgv0xp3";
  kleeWeights = {
    Regular = "0flvis3az512yl16s7wg8fs0wp4fi2hj8551y2nycanc63q66h5z";
    SemiBold = "1z83nc1254hw28piam6nkq8zx7m7wyz5hz8zxx1i3ji3di1fqcdh";
  };
  # Static weights of a face, and its licence once.
  installWeights =
    face: weights: license: dir:
    pkgs.lib.concatStrings (
      pkgs.lib.mapAttrsToList (weight: sha256: ''
        install -Dm444 ${(face weight sha256).font} $out/share/fonts/truetype/${dir}-${weight}.ttf
      '') weights
    )
    + ''
      install -Dm444 ${license} $out/share/licenses/${pkgs.lib.toLower dir}/OFL.txt
    '';
in
pkgs.symlinkJoin {
  name = "nixbook-shell-fonts";
  paths = [
    (pkgs.runCommand "nixbook-shell-google-fonts" { } ''
      install -Dm444 ${googleSansFlex.font} $out/share/fonts/truetype/GoogleSansFlex.ttf
      install -Dm444 ${googleSansFlex.license} $out/share/licenses/google-sans-flex/OFL.txt
      install -Dm444 ${spaceGrotesk.font} $out/share/fonts/truetype/SpaceGrotesk.ttf
      install -Dm444 ${spaceGrotesk.license} $out/share/licenses/space-grotesk/OFL.txt
      ${pkgs.lib.concatStrings (
        pkgs.lib.mapAttrsToList (weight: sha256: ''
          install -Dm444 ${(rajdhani weight sha256).font} $out/share/fonts/truetype/Rajdhani-${weight}.ttf
        '') rajdhaniWeights
      )}
      install -Dm444 ${(rajdhani "Bold" rajdhaniWeights.Bold).license} $out/share/licenses/rajdhani/OFL.txt
      ${installWeights zenMaru zenMaruWeights (zenMaru "Bold" zenMaruWeights.Bold).license
        "ZenMaruGothic"
      }
      ${installWeights klee kleeWeights (klee "Regular" kleeWeights.Regular).license "KleeOne"}
    '')
    pkgs.readexpro
  ];
  meta.license = pkgs.lib.licenses.ofl;
}
