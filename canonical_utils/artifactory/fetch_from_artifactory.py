#!/usr/bin/env python3
"""
USAGE EXAMPLE:
    ./fetch_from_artifactory.py --artifactory-url url.txt \
        --artifact-path '/foo/pool/b/bar/artifact.tar.gz' \
            --token-file token_file --output-file foo.tar.gz
"""
import argparse
from artifactory import ArtifactoryPath


parser = argparse.ArgumentParser()
parser.add_argument(
    "--artifact-path",
    help="Path, as an URL suffix to --artifact-url, of the artifact to fetch",
    required=True,
)
parser.add_argument(
    "--artifactory-url-file",
    help="Text file with the Artifactory base URL in plain text",
    required=True,
)
parser.add_argument(
    "--token-file",
    help="Token file with the plain text token for Artifactory authentication",
    required=True,
)
parser.add_argument(
    "--output-file",
    help="Where to save the artifact",
    required=False,
)

args = parser.parse_args()
with open(args.token_file) as token_file:
    token = token_file.read().splitlines()[0]

with open(args.artifactory_url_file) as url_file:
    base_url = url_file.read().splitlines()[0].rstrip("/")
    
full_url = base_url + "/" + args.artifact_path
path = ArtifactoryPath(full_url, token=token)

output_file = args.output_file
if not output_file:
    output_file = args.artifact_path.rstrip("/").split("/")[-1]

with path.open() as fd, open(output_file, "wb") as out:
    out.write(fd.read())

print(f"Fetched {output_file} from Artifactory")
