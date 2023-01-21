# Because programmatically changing the independent variables is hard

function passenger_vehicles()
    return Dict(
        "null" => (formula=@formula(y ~ 1), link=nothing),
        "log-null" => (formula=@formula(y ~ log(passenger_vehicles)), link=IdentityLink()),
        "power" => (
            formula=@formula(y ~ 1 + log(passenger_vehicles)),
            link=LogLink()),
        "log-log" => (
            formula=@formula(log(y) ~ 1 + log(passenger_vehicles)),
            link=IdentityLink()),
        "linear" => (
            formula=@formula(y ~ 1 + passenger_vehicles),
            link=IdentityLink()),
        "quadratic" => (
            formula=@formula(y ~ 1 + passenger_vehicles + passenger_vehicles^2),
            link=IdentityLink()),
    )
end

function ev_registrations()
    return Dict(
        "null" => (formula=@formula(y ~ 1), link=nothing),
        "log-null" => (formula=@formula(y ~ log(ev_registrations)), link=IdentityLink()),
        "power" => (
            formula=@formula(y ~ 1 + log(ev_registrations)),
            link=LogLink()),
        "log-log" => (
            formula=@formula(log(y) ~ 1 + log(ev_registrations)),
            link=IdentityLink()),
        "linear" => (
            formula=@formula(y ~ 1 + ev_registrations),
            link=IdentityLink()),
        "quadratic" => (
            formula=@formula(y ~ 1 + ev_registrations + ev_registrations^2),
            link=IdentityLink()),
    )
end

function population()
    return Dict(
        "null" => (formula=@formula(y ~ 1), link=nothing),
        "log-null" => (formula=@formula(y ~ log(population)), link=IdentityLink()),
        "power" => (
            formula=@formula(y ~ 1 + log(population)),
            link=LogLink()),
        "log-log" => (
            formula=@formula(log(y) ~ 1 + log(population)),
            link=IdentityLink()),
        "linear" => (
            formula=@formula(y ~ 1 + population),
            link=IdentityLink()),
        "quadratic" => (
            formula=@formula(y ~ 1 + population + population^2),
            link=IdentityLink()),
    )
end

function pop_density()
    return Dict(
        "null" => (formula=@formula(y ~ 1), link=nothing),
        "log-null" => (formula=@formula(y ~ log(pop_density)), link=IdentityLink()),
        "power" => (
            formula=@formula(y ~ 1 + log(pop_density)),
            link=LogLink()),
        "log-log" => (
            formula=@formula(log(y) ~ 1 + log(pop_density)),
            link=IdentityLink()),
        "linear" => (
            formula=@formula(y ~ 1 + pop_density),
            link=IdentityLink()),
        "quadratic" => (
            formula=@formula(y ~ 1 + pop_density + pop_density^2),
            link=IdentityLink()),
    )
end

function passenger_vehicle_density()
    return Dict(
        "null" => (formula=@formula(y ~ 1), link=nothing),
        "log-null" => (formula=@formula(y ~ log(passenger_vehicle_density)), link=IdentityLink()),
        "power" => (
            formula=@formula(y ~ 1 + log(passenger_vehicle_density)),
            link=LogLink()),
        "log-log" => (
            formula=@formula(log(y) ~ 1 + log(passenger_vehicle_density)),
            link=IdentityLink()),
        "linear" => (
            formula=@formula(y ~ 1 + passenger_vehicle_density),
            link=IdentityLink()),
        "quadratic" => (
            formula=@formula(y ~ 1 + passenger_vehicle_density + passenger_vehicle_density^2),
            link=IdentityLink()),
    )
end

function ev_registration_density()
    return Dict(
        "null" => (formula=@formula(y ~ 1), link=nothing),
        "log-null" => (formula=@formula(y ~ log(ev_registration_density)), link=IdentityLink()),
        "power" => (
            formula=@formula(y ~ 1 + log(ev_registration_density)),
            link=LogLink()),
        "log-log" => (
            formula=@formula(log(y) ~ 1 + log(ev_registration_density)),
            link=IdentityLink()),
        "linear" => (
            formula=@formula(y ~ 1 + ev_registration_density),
            link=IdentityLink()),
        "quadratic" => (
            formula=@formula(y ~ 1 + ev_registration_density + ev_registration_density^2),
            link=IdentityLink()),
    )
end
