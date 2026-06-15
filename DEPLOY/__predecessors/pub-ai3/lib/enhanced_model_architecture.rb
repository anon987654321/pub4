# encoding: utf-8
# Enhanced model architecture based on recent research

class EnhancedModelArchitecture
  def initialize(model, optimizer, loss_function)
    @model = model
    @optimizer = optimizer
    @loss_function = loss_function
  end

  def train(data, labels)
    predictions = @model.predict(data)
    loss = @loss_function.calculate(predictions, labels)
    @optimizer.step(loss)
  end

  def evaluate(test_data, test_labels)
    predictions = @model.predict(test_data)
    accuracy = calculate_accuracy(predictions, test_labels)
    accuracy
  end

  private

  def calculate_accuracy(predictions, labels)
    correct = predictions.zip(labels).count { |pred, label| pred == label }
    correct / predictions.size.to_f
  end
end
