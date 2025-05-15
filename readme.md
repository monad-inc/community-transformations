# Monad Community Transformations - Contribution Guidelines

Thank you for your interest in contributing to the Monad Community Transformations repository! This repository serves as a central hub for transformations created by both Monad and the community, which can be shared across the Monad SAAS application.

## Repository Purpose

The transformations in this repository are automatically synced to the Monad SaaS platform every hour, making them immediately available to all users. This enables the community to collaboratively build, share, and improve transformations for common use cases.

## Getting Started

### Prerequisites

- Basic understanding of transformation logic and YAML syntax
- Familiarity with the Monad platform
- GitHub account for submitting contributions

### Structure

Transformations should follow the existing repository organization:
```
transformation-category/version/vendor/vendor-datatype.yaml
```

For example:
```
ocsf/v1.1.0/okta/okta-systemlog.yaml
```

Each transformation file should have a clear, descriptive filename that indicates the vendor and data type, and should follow our standard format as demonstrated in the example below.

## Transformation File Format

Transformations should follow this structure:

```yaml
name: "Descriptive Transformation Name"
description: "Clear description of what the transformation does"
author: "Your Name or Organization"
contributors:
  - "https://github.com/YourGitHubHandle"
inputs:
  - "source-data-type"
tags:
  - "version-tag"
  - "relevant-tag1"
  - "relevant-tag2"
config:
  operations:
    - operation: "operation-type"
      arguments:
        key: ""
        query: |
          # Your transformation logic here
```

## Contribution Process

### 1. Get Started with the Repository

Clone the repository:
```bash
git clone https://github.com/monad-inc/community-transformations.git
```

### 2. Create a Feature Branch

Create a new branch for your transformation:
```bash
git checkout -b feature/your-transformation-name
```

### 3. Develop Your Transformation

Create your transformation following the guidelines below:

- **Naming**: Use clear, descriptive names that indicate the transformation's purpose
- **Documentation**: Include detailed comments explaining complex logic
- **Testing**: Test your transformation thoroughly with various inputs
- **Best Practices**: Follow the coding standards and best practices outlined below

### 4. Submit a Pull Request

- Push your changes to your forked repository
- Create a pull request to the main repository
- Include a detailed description of your transformation and its use cases

### 5. Review Process

- The Monad team will review your pull request
- You may receive feedback or requests for changes
- Once approved, your transformation will be merged and become available in the next sync

### Documentation Requirements

Each transformation should include:

1. **Header Documentation**: Name, description, author, and purpose
2. **Input/Output Documentation**: Clear description of expected inputs and outputs
3. **Function Documentation**: Explanation of each function's purpose
4. **Usage Examples**: Simple examples demonstrating the transformation

## Testing Your Transformations

Before submitting, ensure your transformation:

1. Handles expected inputs correctly
2. Properly processes edge cases
3. Handles null or missing values gracefully
4. Produces the expected output format
5. Performs efficiently with larger datasets

## Repository Organization

When adding a new transformation:

1. Place your transformation in a logical location within the repository structure
2. Follow the existing organization pattern: `/output-format/version/vendor/transformation-file.yaml`
3. If adding to an existing vendor folder, maintain consistency with other transformations
4. Create new vendor folders as needed under the appropriate version directory
5. Use descriptive filenames that indicate the specific data source and purpose

For example, following our current structure:
- `/ocsf/v1.1.0/crowdstrike/crowdstrike-device-details.yaml`
- `/ocsf/v1.1.0/okta/okta-systemlog.yaml`
- `/ocsf/v1.1.0/tenable/tenable-vulnerabilities.yaml`

This organized structure helps maintain consistency and makes it easier for users to find relevant transformations.

## Attribution

Proper attribution on the Monad Platform will be maintained through the `author` and `contributors` fields in each transformation.

- **For new transformations**:
    - Set the `author` field to your GitHub profile URL (e.g., "https://github.com/YourUsername")
    - Include yourself in the `contributors` list with the same URL

- **When updating existing transformations**:
    - Add your GitHub profile URL to the `contributors` list
    - Do not modify the original `author` field

Example:
```yaml
author: "https://github.com/OriginalAuthor"
contributors:
  - "https://github.com/OriginalAuthor"
  - "https://github.com/YourUsername"
```

This ensures proper credit is given to both original creators and those who improve transformations over time.

## Community Support

- For questions, join our [Community Slack Channel](#)
- Report issues on the GitHub repository
- For feature requests, please use the issue template



---

Thank you for contributing to the Monad community! Your transformations help make our platform more powerful and useful for everyone.