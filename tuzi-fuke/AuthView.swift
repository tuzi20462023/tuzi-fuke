//
//  AuthView.swift
//  tuzi-fuke
//
//  简单的登录/注册界面（MVP版本）
//

import SwiftUI
import Supabase

struct AuthView: View {
    @ObservedObject var authManager: AuthManager

    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        ZStack {
            // 背景渐变
            LinearGradient(
                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 30) {
                    // Logo
                    VStack(spacing: 16) {
                        Image(systemName: "globe.asia.australia.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: .blue.opacity(0.5), radius: 10)

                        Text("地球新主")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("末世生存策略游戏")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 80)

                    // 登录/注册切换
                    Picker("", selection: $isSignUp) {
                        Text("登录").tag(false)
                        Text("注册").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 40)

                    // 表单
                    VStack(spacing: 16) {
                        // 邮箱输入
                        TextField("邮箱", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()

                        // 密码输入
                        SecureField("密码", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(isSignUp ? .newPassword : .password)

                        // 登录/注册按钮
                        Button(action: handleAuth) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text(isSignUp ? "注册" : "登录")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isValidInput ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(!isValidInput || isLoading)
                    }
                    .padding(.horizontal, 30)

                    // 提示文字
                    if isSignUp {
                        Text("注册后会自动登录")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
            }
        }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    // MARK: - 输入验证

    private var isValidInput: Bool {
        let emailValid = email.contains("@") && email.contains(".")
        let passwordValid = password.count >= 6
        return emailValid && passwordValid
    }

    // MARK: - 处理登录/注册

    private func handleAuth() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                if isSignUp {
                    // 注册
                    try await signUp()
                } else {
                    // 登录
                    try await authManager.signIn(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isLoading = false
        }
    }

    // MARK: - 注册方法

    private func signUp() async throws {
        print("🔐 [AuthView] 开始注册: \(email)")

        let supabase = SupabaseManager.shared.client

        // Supabase 注册
        let response = try await supabase.auth.signUp(
            email: email,
            password: password
        )

        // 检查是否需要邮箱验证
        if response.session != nil {
            // 不需要验证，直接登录
            try await authManager.signIn(email: email, password: password)
            print("✅ [AuthView] 注册并登录成功")
        } else {
            // 需要验证邮箱
            throw NSError(
                domain: "AuthError",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "注册成功！请检查邮箱完成验证后再登录。"]
            )
        }
    }
}

#Preview {
    AuthView(authManager: AuthManager.shared)
}
