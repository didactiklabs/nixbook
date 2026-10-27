# A Python package set where mcp is its last 1.x release (PyPI's wheel).
# nixpkgs moved to mcp 2, which marks its fastmcp 3 broken; fastmcp 3 still
# works on mcp 1. Used by the overlay's mcp-nixos and by
# customPkgs.linkedin-mcp-server. Drop it once nixpkgs has a fastmcp for mcp 2.
{ pkgs }:
pythonPackages:
pythonPackages.overrideScope (
  _: super: {
    mcp = super.buildPythonPackage rec {
      pname = "mcp";
      version = "1.30.0";
      format = "wheel";
      src = pkgs.fetchurl {
        url = "https://files.pythonhosted.org/packages/f5/f4/e58bc33317c92a0203664daaf00bf6f41166cc0149e5d6870a03f7cd004a/mcp-${version}-py3-none-any.whl";
        hash = "sha256-Zm7bUAlQPhBHydYDRqdW+UsmHwXMJiXyPUHHKP/EhNA=";
      };
      dependencies =
        with super;
        [
          anyio
          httpx
          httpx-sse
          jsonschema
          pydantic
          pydantic-settings
          pyjwt
          python-multipart
          sse-starlette
          starlette
          typing-extensions
          typing-inspection
          uvicorn
        ]
        ++ super.pyjwt.optional-dependencies.crypto;
      pythonImportsCheck = [ "mcp.server.fastmcp" ];
    };
    # The OAuth proxy's stored client gains a field with mcp 1.x; nothing
    # here uses the OAuth proxy.
    fastmcp = super.fastmcp.overridePythonAttrs (old: {
      disabledTests = (old.disabledTests or [ ]) ++ [ "test_storage_data_structure" ];
    });
  }
)
