import encoding from "k6/encoding";

export interface IEndpoint {
    path: string;
    needsAuth: boolean;
    okStatus?: number[]; // response codes counted as success; defaults to [200]
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
    // content-file: fetch a package -> 302 redirect to object storage (the "download" path). The
    // redirect IS pulp-content's work, so it counts 302 as success and does not follow it (following
    // would time S3, not pulp). aiodns-3.2.0.tar.gz is a small (~8 KB) released sdist.
    "content-file": {
        path: "/api/pulp-content/default/my-pypi/aiodns-3.2.0.tar.gz",
        needsAuth: true,
        okStatus: [200, 302]
    },
    // content-index: fetch a PyPI simple index -> 200, HTML that pulp-content generates and streams.
    "content-index": {
        path: "/api/pulp-content/default/my-pypi/simple/aiodns/",
        needsAuth: true
    },
} satisfies Record<string, IEndpoint>;

export type EndpointNameType = keyof typeof ALL_ENDPOINTS;

export const getHeaders = (args: {
    endpoint: IEndpoint, user: string, password: string
}): Record<string, string> => {
    const { endpoint, user, password } = args;
    return endpoint.needsAuth ?
        {
            "Authorization": "Basic " + encoding.b64encode(`${user}:${password}`)
        }
        : {}
}
