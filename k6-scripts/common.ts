import encoding from "k6/encoding";

interface IEndpoint {
    path: string;
    needsAuth: boolean;
}

export const ALL_ENDPOINTS = {
    status: {
        path: "/api/pulp/api/v3/status/",
        needsAuth: false
    },
    repositories: {
        path: "/api/pulp/default/api/v3/repositories/",
        needsAuth: true
    },
} satisfies Record<string, IEndpoint>;

export type EndpointNameType = keyof typeof ALL_ENDPOINTS;

export const getHeaders = (args: {
    endpoint: IEndpoint, user: string, password: string
}): Record<string, string> => {
    const {endpoint, user, password} = args;
    return endpoint.needsAuth ?
        {
            "Authorization": "Basic " + encoding.b64encode(`${user}:${password}`)
        }
        : {}
}
