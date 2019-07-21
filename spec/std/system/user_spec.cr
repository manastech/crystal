require "spec"
require "system/user"

USER_NAME = {{ `id -un`.stringify.chomp }}
USER_ID   = {{ `id -u`.stringify.chomp }}

describe System::User do
  describe "find" do
    it "returns a user by name" do
      user = System::User.find(name: USER_NAME)

      user.should be_a(System::User)
      user.username.should eq(USER_NAME)
      user.user_id.should eq(USER_ID)
    end

    it "raises on a nonexistent user" do
      expect_raises System::User::NotFoundError, "No such user" do
        System::User.find(name: "this_user_does_not_exist")
      end
    end

    it "returns a user by id" do
      user = System::User.find(id: USER_ID)

      user.should be_a(System::User)
      user.user_id.should eq(USER_ID)
      user.username.should eq(USER_NAME)
    end

    it "raises on nonexistent user id" do
      expect_raises System::User::NotFoundError, "No such user" do
        System::User.find(id: "1234567")
      end
    end
  end

  describe "find?" do
    it "returns a user by name" do
      user = System::User.find?(name: USER_NAME).not_nil!

      user.should be_a(System::User)
      user.username.should eq(USER_NAME)
      user.user_id.should eq(USER_ID)
    end

    it "returns nil on nonexistent user" do
      user = System::User.find?(name: "this_user_does_not_exist")
      user.should eq(nil)
    end

    it "returns a user by id" do
      user = System::User.find?(id: USER_ID).not_nil!

      user.should be_a(System::User)
      user.user_id.should eq(USER_ID)
      user.username.should eq(USER_NAME)
    end

    it "returns nil on nonexistent user id" do
      user = System::User.find?(id: "1234567")
      user.should eq(nil)
    end
  end

  describe "username" do
    it "is the same as the source name" do
      System::User.find(name: USER_NAME).username.should eq(USER_NAME)
    end
  end

  describe "user_id" do
    it "is the same as the source ID" do
      System::User.find(id: USER_ID).user_id.should eq(USER_ID)
    end
  end

  describe "group_id" do
    it "calls without raising" do
      System::User.find(name: USER_NAME).group_id
    end
  end

  describe "directory" do
    it "calls without raising" do
      System::User.find(name: USER_NAME).directory
    end
  end

  describe "shell" do
    it "calls without raising" do
      System::User.find(name: USER_NAME).shell
    end
  end

  describe "to_s" do
    it "returns a string representation" do
      System::User.find(name: USER_NAME).to_s.should eq("#{USER_NAME} (#{USER_ID})")
    end
  end
end
