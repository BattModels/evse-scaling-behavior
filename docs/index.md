---
layout: home
---

<p align="center">
    <a href="{% link map.html %}">
        <img width="80%" src="assets/ev_pop_residuals.svg"/>
    </a>
</p>

Enabling widespread electric vehicle adoption will require a substantial build-out of charging infrastructure.
Currently, _48% of counties lack any public charging infrastructure_ and by our estimates, no county has sufficient infrastructure for widespread adoption[^1].
However, current techniques for estimating charging infrastructure needs are limited and often require significant computational resources.
We need a simple, robust framework for estimating infrastructure needs and evaluating the Infrastructure Gap -- the difference between how many chargers are needed and how many are deployed.

Using [Urban Scaling Theory][scale], we've estimated the number of charging stations needed to reach parity[^2] with gasoline stations and created [an interactive map of our estimates][map].
For example, in Washtenaw County, Michigan[^3], we estimate an 83-fold increase in charging infrastructure is needed.

We've published our [paper] as an Open Access brief report on PNAS Nexus, and have publicly released a [dataset of our predictions and the input datasets](dataset).


[scale]: https://www.ted.com/talks/geoffrey_west_the_surprising_math_of_cities_and_corporations?utm_campaign=tedspread&utm_medium=referral&utm_source=tedcomshare
[map]: map.html
[paper]: https://doi.org/10.1093/pnasnexus/pgad341
[dataset]: https://doi.org/10.5281/zenodo.5784659

[^1]: Our estimates are based on data ending before December, 31st, 2020, and do not reflect more recent developments.
[^2]: We've defined parity as the number of charging ports needed to enable the same vehicle miles traveled as a gasoline pump.
[^3]: The home of the University of Michigan
