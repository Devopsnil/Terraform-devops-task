provider "aws" {
    region = "us-est-1"
}

terraform {
    required_providers {
      aws = {
        source = "hashicrop/aws"
        version = "5.0"
      }
    }
}