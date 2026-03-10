{ pkgs }:
let
  sources = import ../npins;
  crdWizardSrc = sources.crd-wizard;
in
pkgs.buildGoModule {
  pname = "crd-wizard";
  version = "nix";

  src = crdWizardSrc;

  vendorHash = "sha256-9+HZL11PQuIndbXcZg+cYPBESX9eSWrKsw9/5crXzGw=";

  subPackages = [ "." ];

  meta = {
    homepage = "https://github.com/pehlicd/crd-wizard";
    description = "CR(D) Wizard is a web and tui based dashboard designed to provide a clear and intuitive interface for visualizing and exploring Kubernetes Custom Resource Definitions (CRDs) and their corresponding Custom Resources (CRs). It helps k8s users to quickly understand the state of their custom controllers and the resources they manage.";
    mainProgram = "crd-wizard";
  };
}
