import Foundation

/// Progress for the four-step setup guide. Only identity is required; the
/// remaining steps can be completed later from Settings.
public struct OnboardingState: Codable, Equatable, Sendable {
  public var completed: Bool
  public var currentStep: Int
  public var identityCompleted: Bool
  public var photoConfigured: Bool
  public var memoryConfigured: Bool
  public var apiConfigured: Bool

  public init(
    completed: Bool = false, currentStep: Int = 1,
    identityCompleted: Bool = false, photoConfigured: Bool = false,
    memoryConfigured: Bool = false, apiConfigured: Bool = false
  ) {
    self.completed = completed
    self.currentStep = min(4, max(1, currentStep))
    self.identityCompleted = identityCompleted
    self.photoConfigured = photoConfigured
    self.memoryConfigured = memoryConfigured
    self.apiConfigured = apiConfigured
  }
}
