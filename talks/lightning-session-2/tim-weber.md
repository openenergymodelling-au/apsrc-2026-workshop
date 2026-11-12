---
# Incomplete: title and abstract to come.
order: 6

title: "FIRM_CE"

authors:
  - name: Timothy Weber
    affiliation: The Australian National University
    affiliation-short: ANU

links:
  - label: Lu et al. (2021)
    url: https://doi.org/10.1016/j.energy.2020.119678 
  - label: Weber et al. (2026)
    url: https://doi.org/10.1016/j.xcrp.2026.103523 
  - label: FIRM_CE
    url: https://github.com/TimWeberRE100/FIRM_CE
---

FIRM_CE is an open-source tool for modelling electricity grid investment and testing reliability over decades of weather data. It is based on the FIRM framework, originally developed by Lu et al. (2021)  and adapted in Weber et al. (2026) . The purpose of FIRM_CE is to rapidly evaluate thousands (or millions) of grid configurations very quickly through an evolutionary optimisation, testing each configuration for reliability and cost. 

Conventional linear programs require separate variables for each investment and dispatch decision, which can drive up computation time when using decades of high-resolution data. FIRM_CE only optimises the investment decision variables, with simple business rules managing the dispatch of generators instead. The fast dispatch rules avoid the need for temporal aggregation methods that skew away from long-duration storage investment.

The RE100 Group is currently developing techniques for performing modelling to generate alternatives (MGA) using the FIRM framework. Using MGA techniques, FIRM_CE can explore thousands of grid configurations in the near-optimal space, allowing decision makers to consider a vast number of alternative pathways that all have the exact same cost (within the very high margin of uncertainty).

