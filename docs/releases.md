# Release Process

[This process is for the Microsoft maintainers of this repo]

## Prerequisites for creating a release

- Write permissions on GitHub repo [Azure/GuardrailsSolutionAccelerator](https://github.com/Azure/GuardrailsSolutionAccelerator)
- [DevOps](https://dev.azure.com/guardrailssolutionaccelerator): a Service Connection named 'Guardrails Test Deployment Azure Connection' with sufficient rights to the target Azure tenant. 
- [DevOps](https://dev.azure.com/guardrailssolutionaccelerator): a Service Connection named 'Guardrails GitHub Connection' with write permissions to the Azure\GuardrailsSolutionAccelerator GitHub repo. Due to limitations on the GitHub org, this Service Connection currently relies on a scoped GitHub Personal Access Token, which is associated with an individual's GitHub account and subject to expiration. 
- [DevOps](https://dev.azure.com/guardrailssolutionaccelerator): a Service Connection named 'ESRP Guardrails Accelerator Signing' with access configured to Microsoft's internal ESRP code signing service

## Process to publish a pre-release

Execution of the pre-release creation pipeline in Azure DevOps requires a new tag be added to trigger the pipeline. The tag must match the pattern: 'prerelease-v1.*'

A pre-release release is used to make code updates made between releases available for consumption in new or updated deployments.

```git
# (After all PRs to be included are merged)
git checkout main
git fetch upstream
git reset upstream/main --hard
```

**Update ./setup/tags.json** with the prerelease version number.

```git
git commit -am 'tags-prerelease-v1.0.8.8'
git tag -f prerelease-v1.0.8.8
git push upstream tag prerelease-v1.0.8.8
```

Once the tag is pushed to GitHub, the tag created above will trigger the Pipeline named ['Azure.GuardrailsSolutionAccelerator Prerelease Pipeline' in Azure DevOps](https://dev.azure.com/guardrailssolutionaccelerator/GuardrailsSolutionAccelerator/_build?definitionId=10). Navigate to Azure DevOps to monitor the progress of the pipeline and address any issues. If the pipeline fails, a release will not be created in GitHub. 

## Process to publish a full release

Execution of the Release creation pipeline in Azure DevOps requires a new tag be added to trigger the pipeline. The tag must match the pattern: 'v1.*'

```git
# (After all PRs to be included are merged)
git checkout main
git fetch upstream
git reset upstream/main --hard
```

**Update ./setup/tags.json** with the prerelease version number.

```git
git commit -am 'tags-v1.0.8'
git tag -f v1.0.8
git push upstream tag v1.0.8
```

Once the tag is pushed to GitHub, the tag created above will trigger the Pipeline named ['Azure.GuardrailsSolutionAccelerator Release Pipeline' in Azure DevOps](https://dev.azure.com/guardrailssolutionaccelerator/GuardrailsSolutionAccelerator/_build?definitionId=11). Navigate to Azure DevOps to monitor the progress of the pipeline and address any issues. If the pipeline fails, a release will not be created in GitHub. 