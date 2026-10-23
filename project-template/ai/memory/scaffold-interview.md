---
name: scaffold-interview
description: The questionnaire answers this {{SPECIES_NAME}} index project was scaffolded from.
metadata:
  type: project
  author: <agent>
  created: <YYYY-MM-DD>
---

# Scaffold interview — {{SPECIES_NAME}}

Fill this in during `index-new-project` with the actual answers. Keep it in sync with
`config.yaml` (config holds the machine-readable values; this holds the reasoning).

- **Species / `filter_sp`**: {{SPECIES_NAME}} (*{{SPECIES_LATIN}}*) — Norwegian commonname
  value(s): _<confirm via BAIT taxaindex>_.
- **Surveys included** (with true absences): _<list; why these>_.
- **Distribution / SPD**: _<northern-offshore or southern-coastal; USE_SPD and why>_.
- **Gear width**: _<normally 25 m for all trawls; retain `geartype` as a fixed effect. Use
  `per_gear` only when a project has a documented reason to estimate separate widths>_.
- **Response & products**: _<biomass/abundance; over-X-cm threshold; length-group breaks>_.
- **Assessment model**: _<e.g. SPiCT; drives spatiotemporal/year-effect choice for the
  selected index>_.
- **Years**: _<first year>_.
- **Domain**: _<study area / prediction region source; CRS; grid km; mesh cutoff km; barrier
  yes/no>_.
- **Russian data**: _<included by default; excluded only if noted>_.
- **Outputs**: _<which are official / exploratory / draft>_.

**Open questions / to confirm:** _<anything ambiguous flagged during planning>_.

## Authorship and reporting

Record confirmed human authors, affiliation IDs and names, and the exact AI model list and
roles. All workflow reports follow wise-writing data-report style and conventions.
