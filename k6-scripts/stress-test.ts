import { Options } from "k6/options";
import { ALL_ENDPOINTS, EndpointNameType, IEndpoint, getHeaders } from "./common.ts";
import http from "k6/http";
import { check } from "k6";
import exec from "k6/execution";

export const options: Options = {
    insecureSkipTLSVerify: true,
    stages: [
        { target: 96, duration: "90s" },
        { target: 200, duration: "90s" },
        { target: 400, duration: "90s" },
        { target: 600, duration: "90s" },
        { target: 0, duration: "30s" }, // cool down
    ],
};

const request = () => {
    const endpoint: IEndpoint = ALL_ENDPOINTS[__ENV.ENDPOINT as EndpointNameType];
    let headers = getHeaders({
        endpoint,
        user: __ENV.PULP_USER,
        password: __ENV.PULP_PASS
    });
    const response = http.get(`${__ENV.BASE_URL}${endpoint.path}`, {
        headers,
        timeout: "60s",
        redirects: 0, // keep pulp-content's 302 instead of following it to object storage
    });
    if (endpoint.needsAuth && response.status === 401) {
        exec.test.abort(`Received 401 for auth-required endpoint "${__ENV.ENDPOINT}". Check PULP_USER/PULP_PASS.`);
    }
    const okStatus = endpoint.okStatus ?? [200];
    check(response, {
        [`status is ${okStatus.join(" or ")}`]: (r) => okStatus.includes(r.status)
    });
}
export default request;
