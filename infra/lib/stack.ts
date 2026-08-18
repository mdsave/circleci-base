import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import * as ecr from "aws-cdk-lib/aws-ecr";
import * as iam from "aws-cdk-lib/aws-iam";
import * as kms from "aws-cdk-lib/aws-kms";

export interface EcrPublishStackProps extends cdk.StackProps {
  /** Name of the ECR repository holding the CI base image. */
  ecrRepoName: string;
  /**
   * CircleCI organization UUID, used as both the OIDC issuer path and audience.
   * When omitted, no OIDC provider is created and the role is assumable by SSO only.
   */
  circleciOrgId?: string;
  /** CircleCI project UUID. When omitted, any project in the org may assume the role. */
  circleciProjectId?: string;
  /** SSO permission set name whose assumed role may publish (e.g. "marketplace-admin"). */
  ssoPermissionSet: string;
}

export class EcrPublishStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: EcrPublishStackProps) {
    super(scope, id, props);

    const repository = new ecr.Repository(this, "Repository", {
      repositoryName: props.ecrRepoName,
      imageScanOnPush: true,
      imageTagMutability: ecr.TagMutability.MUTABLE,
      encryption: ecr.RepositoryEncryption.AES_256,
      // Branch tags are meaningful; only reap untagged layers.
      lifecycleRules: [
        {
          description: "Expire untagged images after 14 days",
          tagStatus: ecr.TagStatus.UNTAGGED,
          maxImageAge: cdk.Duration.days(14),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // Asymmetric key: cosign signs with kms:Sign and verifies via the public key.
    // Automatic rotation is unavailable for asymmetric keys, so it is not set.
    const signingKey = new kms.Key(this, "CosignSigningKey", {
      description: `cosign signing key for ${props.ecrRepoName} container images`,
      keySpec: kms.KeySpec.ECC_NIST_P256,
      keyUsage: kms.KeyUsage.SIGN_VERIFY,
      alias: `cosign/${props.ecrRepoName}`,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      pendingWindow: cdk.Duration.days(30),
    });

    // Base trust path: engineers running `make docker-deploy` under SSO.
    // IAM forbids wildcards in a principal ARN, so the account is trusted and
    // narrowed to the permission set's generated role via aws:PrincipalArn.
    const publishRole = new iam.Role(this, "EcrPublishRole", {
      roleName: `${props.ecrRepoName}-publisher`,
      description: `Publish and cosign-sign ${props.ecrRepoName} images`,
      maxSessionDuration: cdk.Duration.hours(1),
      assumedBy: new iam.AccountPrincipal(this.account).withConditions({
        StringLike: {
          "aws:PrincipalArn": `arn:aws:iam::${this.account}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_${props.ssoPermissionSet}_*`,
        },
      }),
    });

    // Optional second trust path: CircleCI exchanging an OIDC token for credentials.
    if (props.circleciOrgId) {
      const orgId = props.circleciOrgId;
      const oidcProvider = new iam.OpenIdConnectProvider(this, "CircleCiOidcProvider", {
        url: `https://oidc.circleci.com/org/${orgId}`,
        clientIds: [orgId],
      });

      const subject = props.circleciProjectId
        ? `org/${orgId}/project/${props.circleciProjectId}/*`
        : `org/${orgId}/*`;

      publishRole.assumeRolePolicy?.addStatements(
        new iam.PolicyStatement({
          actions: ["sts:AssumeRoleWithWebIdentity"],
          principals: [new iam.OpenIdConnectPrincipal(oidcProvider)],
          conditions: {
            StringEquals: { [`oidc.circleci.com/org/${orgId}:aud`]: orgId },
            StringLike: { [`oidc.circleci.com/org/${orgId}:sub`]: subject },
          },
        }),
      );
    }

    // Covers the image push and the cosign signature artifact, which cosign
    // writes into the same repository as a `sha256-<digest>.sig` tag.
    repository.grantPullPush(publishRole);

    signingKey.grant(
      publishRole,
      "kms:Sign",
      "kms:Verify",
      "kms:GetPublicKey",
      "kms:DescribeKey",
    );

    new cdk.CfnOutput(this, "RepositoryUri", { value: repository.repositoryUri });
    new cdk.CfnOutput(this, "PublishRoleArn", { value: publishRole.roleArn });
    new cdk.CfnOutput(this, "CosignKeyUri", { value: `awskms:///alias/cosign/${props.ecrRepoName}` });
  }
}
