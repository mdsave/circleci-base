#!/usr/bin/env node
import * as cdk from "aws-cdk-lib";
import { EcrPublishStack } from "../lib/stack";

const app = new cdk.App();

const account = app.node.tryGetContext("account");
const region = app.node.tryGetContext("region");
const ecrRepoName = app.node.tryGetContext("ecrRepoName");
const ssoPermissionSet = app.node.tryGetContext("ssoPermissionSet");
const circleciOrgId = app.node.tryGetContext("circleciOrgId");
const circleciProjectId = app.node.tryGetContext("circleciProjectId");
const tags: Record<string, string> = app.node.tryGetContext("tags") ?? {};

const REQUIRED_TAGS = [
  "TEAM_OWNER_NAME",
  "TEAM_OWNER_EMAIL",
  "PRODUCT_OWNER_NAME",
  "PRODUCT_OWNER_EMAIL",
  "JIRA_PROJECT",
  "SLACK_CHANNEL",
  "PRODUCT_NAME",
  "PRODUCT_REPO",
];

const missingTags = REQUIRED_TAGS.filter((t) => !tags[t]);
if (missingTags.length > 0) {
  throw new Error(
    `Missing required ownership tags in cdk.json context 'tags': ${missingTags.join(", ")}`,
  );
}

if (!circleciOrgId) {
  console.warn(
    "[warn] No 'circleciOrgId' context: deploying with SSO trust only. " +
      "CircleCI will not be able to assume the publish role. " +
      "Add it later with -c circleciOrgId=<uuid> and redeploy.",
  );
}

const stack = new EcrPublishStack(app, `${ecrRepoName}-ecr-publish`, {
  env: { account, region },
  ecrRepoName,
  circleciOrgId,
  circleciProjectId,
  ssoPermissionSet,
});

// Applied at stack scope so every taggable resource inherits them.
for (const [key, value] of Object.entries(tags)) {
  cdk.Tags.of(stack).add(key, value);
}
