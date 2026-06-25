// Uploads the self-contained Maester HTML report as a standalone GitHub Actions
// artifact and returns a direct URL. Unlike actions/upload-artifact (which always
// wraps files in a ZIP), this calls GitHub's Twirp Artifact API directly with
// mime_type=text/html, so the file is rendered inline in the browser.
//
// Invoked from action.yml via actions/github-script:
//   const upload = require('${{ github.action_path }}/script/Upload-HtmlReportArtifact.js');
//   await upload({ core });
//
// Required environment variables:
//   ACTIONS_RUNTIME_TOKEN, ACTIONS_RESULTS_URL  (exposed inside JS action handlers)
//   GITHUB_SERVER_URL, GITHUB_REPOSITORY, GITHUB_RUN_ID
//   MAESTER_ARTIFACT_NAME  (the desired artifact file name, e.g. maester-report-latest-...html)
//   MAESTER_HTML_PATH      (path to the HTML report file)

const fs = require('fs');
const crypto = require('crypto');

// Extract the workflow run/job backend IDs from the runtime token's `scp` claim
// (format: "Actions.Results:{runId}:{jobId}"). These identify the artifact owner.
function extractBackendIds(jwt) {
  try {
    const parts = jwt.split('.');
    if (parts.length < 2) return [null, null];
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    const scp = payload.scp || '';
    for (const scope of scp.split(' ')) {
      if (scope.startsWith('Actions.Results:')) {
        const segs = scope.split(':');
        if (segs.length >= 3) return [segs[1], segs[2]];
      }
    }
  } catch (err) {
    console.warn(`Failed to extract backend IDs from JWT: ${err.message}`);
  }
  return [null, null];
}

module.exports = async ({ core }) => {
  const filePath = process.env.MAESTER_HTML_PATH || 'test-results/test-results.html';
  if (!fs.existsSync(filePath)) {
    core.warning(`HTML report not found: ${filePath}`);
    return;
  }

  // The runtime token + results URL are only exposed inside JS action handlers
  const runtimeToken = process.env.ACTIONS_RUNTIME_TOKEN;
  const resultsUrl = process.env.ACTIONS_RESULTS_URL;
  if (!runtimeToken || !resultsUrl) {
    core.warning('ACTIONS_RUNTIME_TOKEN / ACTIONS_RESULTS_URL not available; cannot upload HTML artifact.');
    return;
  }

  const [runBackendId, jobBackendId] = extractBackendIds(runtimeToken);
  if (!runBackendId || !jobBackendId) {
    core.warning('Could not extract backend IDs from ACTIONS_RUNTIME_TOKEN.');
    return;
  }

  let origin;
  try {
    origin = new URL(resultsUrl).origin;
  } catch {
    core.warning(`Invalid ACTIONS_RESULTS_URL: ${resultsUrl}`);
    return;
  }
  const artifactName = process.env.MAESTER_ARTIFACT_NAME || 'maester-report.html';
  const authHeaders = {
    'Authorization': `Bearer ${runtimeToken}`,
    'Content-Type': 'application/json'
  };

  // Step 1: CreateArtifact — mime_type=text/html is what makes GitHub render
  // the file inline in the browser instead of serving it as a ZIP download.
  const createResp = await fetch(`${origin}/twirp/github.actions.results.api.v1.ArtifactService/CreateArtifact`, {
    method: 'POST',
    headers: authHeaders,
    body: JSON.stringify({
      workflow_run_backend_id: runBackendId,
      workflow_job_run_backend_id: jobBackendId,
      name: artifactName,
      version: 7,
      mime_type: 'text/html'
    })
  });
  if (!createResp.ok) {
    core.warning(`CreateArtifact failed (${createResp.status}): ${await createResp.text()}`);
    return;
  }
  const { signed_upload_url: signedUploadUrl } = await createResp.json();

  // Step 2: Upload the raw HTML bytes to the signed blob URL (no ZIP wrapping)
  const fileBytes = fs.readFileSync(filePath);
  const sha256 = crypto.createHash('sha256').update(fileBytes).digest('hex');
  const blobResp = await fetch(signedUploadUrl, {
    method: 'PUT',
    headers: {
      'Content-Type': 'text/html',
      'x-ms-blob-type': 'BlockBlob'
    },
    body: fileBytes
  });
  if (!blobResp.ok) {
    core.warning(`Blob upload failed (${blobResp.status}): ${await blobResp.text()}`);
    return;
  }

  // Step 3: FinalizeArtifact
  const finalizeResp = await fetch(`${origin}/twirp/github.actions.results.api.v1.ArtifactService/FinalizeArtifact`, {
    method: 'POST',
    headers: authHeaders,
    body: JSON.stringify({
      workflow_run_backend_id: runBackendId,
      workflow_job_run_backend_id: jobBackendId,
      name: artifactName,
      size: fileBytes.length.toString(),
      hash: `sha256:${sha256}`
    })
  });
  if (!finalizeResp.ok) {
    core.warning(`FinalizeArtifact failed (${finalizeResp.status}): ${await finalizeResp.text()}`);
    return;
  }
  const { artifact_id: artifactId } = await finalizeResp.json();

  const serverUrl = process.env.GITHUB_SERVER_URL || 'https://github.com';
  const repository = process.env.GITHUB_REPOSITORY;
  const runId = process.env.GITHUB_RUN_ID;
  const artifactUrl = `${serverUrl}/${repository}/actions/runs/${runId}/artifacts/${artifactId}`;
  core.info(`Uploaded HTML report (artifact id=${artifactId})`);
  core.setOutput('artifact-url', artifactUrl);
};
