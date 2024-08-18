provider "aws" {
  region = "eu-central-1"
}

resource "local_file" "lambda_index_js" {
  filename = "${path.module}/index.js"
  content  = <<-EOF
    exports.handler = async (event) => {
        const response = {
            statusCode: 200,
            body: JSON.stringify('Hello from AWS Lambda!'),
        };
        return response;
    };
EOF
}

resource "null_resource" "zip_lambda" {
  provisioner "local-exec" {
    command     = "zip my-lambda-function.zip index.js"
    working_dir = path.module
  }

  depends_on = [
    local_file.lambda_index_js
  ]
}

resource "aws_lambda_function" "my_lambda_function" {
  function_name = "MyLambdaFunction"
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  role          = aws_iam_role.lambda_exec.arn
  filename      = "my-lambda-function.zip"

  environment {
    variables = {
      ENV_VAR = "example_value"
    }
  }

  depends_on = [null_resource.zip_lambda]
}

resource "aws_iam_role" "lambda_exec" {
  name = "MyLambdaExecutionRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_api_gateway_rest_api" "my_api_gateway" {
  name        = "MyApiGateway"
  description = "API Gateway for MyLambdaFunction"
}

resource "aws_api_gateway_resource" "my_api_resource" {
  rest_api_id = aws_api_gateway_rest_api.my_api_gateway.id
  parent_id   = aws_api_gateway_rest_api.my_api_gateway.root_resource_id
  path_part   = "mylambda"
}

resource "aws_api_gateway_method" "my_api_method" {
  rest_api_id   = aws_api_gateway_rest_api.my_api_gateway.id
  resource_id   = aws_api_gateway_resource.my_api_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.my_api_gateway.id
  resource_id             = aws_api_gateway_resource.my_api_resource.id
  http_method             = aws_api_gateway_method.my_api_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.my_lambda_function.invoke_arn
}

resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.my_lambda_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.my_api_gateway.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "my_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.my_api_gateway.id
  stage_name  = "dev"

  depends_on = [
    aws_api_gateway_integration.lambda_integration
  ]
}

output "api_gateway_url" {
  description = "The URL of the API Gateway"
  value       = "${aws_api_gateway_deployment.my_api_deployment.invoke_url}/mylambda"
}