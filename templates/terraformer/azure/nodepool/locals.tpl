{{- $uniqueFingerPrint := .Fingerprint }}
{{- $specName          := (index .Data.NodePools 0).Details.Provider.SpecName }}

locals {
  # Accelerated networking can be enabled based on conditions
  # specified here https://azure.microsoft.com/en-us/updates/accelerated-networking-in-expanded-preview/
  # we will look only at VM sizes, since all regions are supported now all reasonable operating systems
  vm_sizes_patterns_{{ $specName }}_{{ $uniqueFingerPrint }} = [
    "D3.*?v3.*",
    "DS3.*?v2.*",
    "DS?4.*?v2.*",
    "DS?5.*?v2.*",
    "DS?12.*?v2.*",
    "DS?13.*?v2.*",
    "DS?14.*?v2.*",
    "DS?15.*?v2.*",
    "Fs?8.*",
    "Fs?16.*",
    "M64m?s.*",
    "M128m?s.*",
    "D8s?.*",
    "D16s?.*",
    "D32s?.*",
    "D64s?.*",
    "E8s?.*",
    "E16s?.*",
    "E32s?.*",
    "E64s?.*",
  ]

  combined_pattern_{{ $specName }}_{{ $uniqueFingerPrint }} = join("|", local.vm_sizes_patterns_{{ $specName }}_{{ $uniqueFingerPrint }})
}
