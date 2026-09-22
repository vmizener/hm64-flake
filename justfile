# List recipes
default:
    just --list

# Run nix formatter
format:
    nix fmt -- $(fd '^[^.]*\.nix$' .)

# Run checks (default: fast). Usage: just check [fast|all|--all|--fast]
check mode="fast": format
    @case "{{mode}}" in \
        all|--all) just check-all ;; \
        fast|--fast) just check-fast ;; \
        *) echo "Unknown mode: '{{mode}}'. Valid options are: fast, all" >&2; exit 1 ;; \
    esac

# Run fast checks
check-fast:
    nix flake check --quiet --show-trace

# Run all checks
check-all:
    nix build ".#all-checks" --no-link -L

# Poll and update new project releases
update-release flags="":
    ./scripts/update-release.sh {{flags}}
