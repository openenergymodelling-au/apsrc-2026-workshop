---
order: 3

title: "Investment uncertainty: modelling the caution that holds investors back"

authors:
  - name: Markus Mannheim
    affiliation: Department of Climate Change, Energy, the Environment and Water / Australian National University
    affiliation-short: DCCEEW / ANU

links:
  - label: Repository
    url: https://github.com/MarkusMannheim/investment_sandbox
  - label: Notebook
    url: https://colab.research.google.com/github/MarkusMannheim/investment_sandbox/blob/main/notebooks/investment_sandbox.ipynb
---

Least-cost models work out what an electricity system should contain, and assume that whatever is cheapest gets built. They cannot show investors holding back in the face of an uncertain future.

We are building an agent-based model of the National Electricity Market that asks who is *willing* to build. This talk presents the Investment sandbox, an open-source, highly simplified version of that model, with one stylised region. Each year its firms, which dislike risk and do not know which future will arrive, decide what to commit using a forecast of what new plant might earn.

In a least-cost model, a higher cost of capital (WACC) makes plant more expensive, but everything still gets built. In the sandbox, cautious firms hold back, so prices rise and demand goes unmet. A government reliability tender shows what intervention changes and what it costs.

The sandbox runs in a Python notebook and each run takes seconds, so participants can try it at the workshop.
