import {Options, Stage} from "k6/options";
import {ALL_ENDPOINTS, EndpointNameType, getHeaders} from "./common.ts";
import http from "k6/http";
import {check} from "k6";
import exec from "k6/execution";

export const options: Options = {
    insecureSkipTLSVerify: true,
    stages: [
        {target: 12, duration: "2m"},
        {target: 24, duration: "2m"},
        {target: 48, duration: "2m"},
        {target: 96, duration: "2m"},
        {target: 0, duration: "30s"}, // cool down
    ],
};

const request = () => {
    const endpoint = ALL_ENDPOINTS[__ENV.ENDPOINT as EndpointNameType];
    let headers = getHeaders({
        endpoint,
        user: __ENV.PULP_USER,
        password: __ENV.PULP_PASS
    });
    const response = http.get(`${__ENV.BASE_URL}${endpoint.path}`, {
        headers,
        timeout: "60s"
    });
    if (endpoint.needsAuth && response.status === 401) {
        exec.test.abort(`Received 401 for auth-required endpoint "${__ENV.ENDPOINT}". Check PULP_USER/PULP_PASS.`);
    }
    check(response, {
        "status is 200": (r) => r.status === 200
    });
}
export default request;
