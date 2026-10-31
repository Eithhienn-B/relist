
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  
  "graphql_public": {
          Tables: {
            [_ in never]: never
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "graphql":
{ Args: { "extensions"?: Json,"operationName"?: string,"query"?: string,"variables"?: Json }; Returns: Json
                           }
          }
          Enums: {
            [_ in never]: never
          }
          CompositeTypes: {
            [_ in never]: never
          }
        },"public": {
          Tables: {
            "campuses": {
                  Row: {
                    "id": number,"is_default": boolean,"location": unknown,"name": string,"school_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "id"?: never,"is_default"?: boolean,"location": unknown,"name": string,"school_id": number
                  }
                  Update: {
                    "id"?: never,"is_default"?: boolean,"location"?: unknown,"name"?: string,"school_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "campuses_school_id_fkey"
      columns: ["school_id"]
isOneToOne: false
      referencedRelation: "schools"
      referencedColumns: ["id"]
    }
                  ]
                },"config": {
                  Row: {
                    "fee_bps": number,"fee_threshold_cents": number,"id": number,"listing_radius_m": number,"location_check_ttl": string,"location_max_accuracy_m": number,"min_price_cents": number,"offer_window": string,"school_id": number | null
                  }
                  ComputedFields: never
                  Insert: {
                    "fee_bps"?: number,"fee_threshold_cents"?: number,"id"?: never,"listing_radius_m"?: number,"location_check_ttl"?: string,"location_max_accuracy_m"?: number,"min_price_cents"?: number,"offer_window"?: string,"school_id"?: number | null
                  }
                  Update: {
                    "fee_bps"?: number,"fee_threshold_cents"?: number,"id"?: never,"listing_radius_m"?: number,"location_check_ttl"?: string,"location_max_accuracy_m"?: number,"min_price_cents"?: number,"offer_window"?: string,"school_id"?: number | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "config_school_id_fkey"
      columns: ["school_id"]
isOneToOne: true
      referencedRelation: "schools"
      referencedColumns: ["id"]
    }
                  ]
                },"listing_photos": {
                  Row: {
                    "created_at": string,"flags": (string)[],"id": string,"listing_id": string,"moderation": string,"path": string,"position": number
                  }
                  ComputedFields: never
                  Insert: {
                    "created_at"?: string,"flags"?: (string)[],"id"?: string,"listing_id": string,"moderation": string,"path": string,"position"?: number
                  }
                  Update: {
                    "created_at"?: string,"flags"?: (string)[],"id"?: string,"listing_id"?: string,"moderation"?: string,"path"?: string,"position"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "listing_photos_listing_id_fkey"
      columns: ["listing_id"]
isOneToOne: false
      referencedRelation: "listings"
      referencedColumns: ["id"]
    }
                  ]
                },"listings": {
                  Row: {
                    "campus_id": number,"category": string,"created_at": string,"description": string,"id": string,"price_cents": number,"school_id": number | null,"search": unknown,"seller_id": string,"status": string,"title": string
                  }
                  ComputedFields: never
                  Insert: {
                    "campus_id": number,"category": string,"created_at"?: string,"description"?: string,"id"?: string,"price_cents": number,"school_id"?: number | null,"search"?: never,"seller_id": string,"status"?: string,"title": string
                  }
                  Update: {
                    "campus_id"?: number,"category"?: string,"created_at"?: string,"description"?: string,"id"?: string,"price_cents"?: number,"school_id"?: number | null,"search"?: never,"seller_id"?: string,"status"?: string,"title"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "listings_campus_id_fkey"
      columns: ["campus_id"]
isOneToOne: false
      referencedRelation: "campuses"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "listings_school_id_fkey"
      columns: ["school_id"]
isOneToOne: false
      referencedRelation: "schools"
      referencedColumns: ["id"]
    }
                  ]
                },"location_checks": {
                  Row: {
                    "accuracy_m": number,"campus_id": number | null,"checked_at": string,"id": number,"passed": boolean,"reason": string | null,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "accuracy_m": number,"campus_id"?: number | null,"checked_at"?: string,"id"?: never,"passed": boolean,"reason"?: string | null,"user_id": string
                  }
                  Update: {
                    "accuracy_m"?: number,"campus_id"?: number | null,"checked_at"?: string,"id"?: never,"passed"?: boolean,"reason"?: string | null,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "location_checks_campus_id_fkey"
      columns: ["campus_id"]
isOneToOne: false
      referencedRelation: "campuses"
      referencedColumns: ["id"]
    }
                  ]
                },"memberships": {
                  Row: {
                    "campus_id": number | null,"created_at": string,"email": string,"grad_season": string,"grad_year": number,"is_18_plus": boolean,"school_id": number | null,"user_id": string
                  }
                  ComputedFields: never
                  Insert: {
                    "campus_id"?: number | null,"created_at"?: string,"email": string,"grad_season": string,"grad_year": number,"is_18_plus": boolean,"school_id"?: number | null,"user_id": string
                  }
                  Update: {
                    "campus_id"?: number | null,"created_at"?: string,"email"?: string,"grad_season"?: string,"grad_year"?: number,"is_18_plus"?: boolean,"school_id"?: number | null,"user_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "memberships_campus_id_fkey"
      columns: ["campus_id"]
isOneToOne: false
      referencedRelation: "campuses"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "memberships_school_id_fkey"
      columns: ["school_id"]
isOneToOne: false
      referencedRelation: "schools"
      referencedColumns: ["id"]
    }
                  ]
                },"school_domains": {
                  Row: {
                    "approved_at": string | null,"domain": string,"evidence_url": string | null,"school_id": number
                  }
                  ComputedFields: never
                  Insert: {
                    "approved_at"?: string | null,"domain": string,"evidence_url"?: string | null,"school_id": number
                  }
                  Update: {
                    "approved_at"?: string | null,"domain"?: string,"evidence_url"?: string | null,"school_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "school_domains_school_id_fkey"
      columns: ["school_id"]
isOneToOne: false
      referencedRelation: "schools"
      referencedColumns: ["id"]
    }
                  ]
                },"schools": {
                  Row: {
                    "colors": NonNullable<Json>,"id": number,"name": string,"short_name": string
                  }
                  ComputedFields: never
                  Insert: {
                    "colors"?: NonNullable<Json>,"id": number,"name": string,"short_name": string
                  }
                  Update: {
                    "colors"?: NonNullable<Json>,"id"?: number,"name"?: string,"short_name"?: string
                  }
                  Relationships: [
                    
                  ]
                }
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "check_location":
{ Args: { "p_accuracy_m": number,"p_lat": number,"p_lng": number }; Returns: {
              "campus_id": number,"campus_name": string,"expires_at": string,"passed": boolean,"reason": string,"school_name": string
            }[]
                           },
"create_listing":
{ Args: { "p_category": string,"p_description": string,"p_price_cents": number,"p_title": string }; Returns: {
              "campus_id": number,
"category": string,
"created_at": string,
"description": string,
"id": string,
"price_cents": number,
"school_id": number | null,
"search": unknown,
"seller_id": string,
"status": string,
"title": string
            }
                          SetofOptions: {
        from: "*"
        to: "listings"
        isOneToOne: true
        isSetofReturn: false
      } },
"create_membership":
{ Args: { "p_grad_season": string,"p_grad_year": number,"p_is_18_plus": boolean }; Returns: {
              "campus_id": number | null,
"created_at": string,
"email": string,
"grad_season": string,
"grad_year": number,
"is_18_plus": boolean,
"school_id": number | null,
"user_id": string
            }
                          SetofOptions: {
        from: "*"
        to: "memberships"
        isOneToOne: true
        isSetofReturn: false
      } },
"nearest_campus":
{ Args: { "p_lat": number,"p_lng": number }; Returns: number
                           }
          }
          Enums: {
            [_ in never]: never
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
      Row: infer R
    }
    ? R
    : never
  : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Insert: infer I
    }
    ? I
    : never
  : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Update: infer U
    }
    ? U
    : never
  : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
  ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
  : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "graphql_public": {
          Enums: {
            
          }
        },"public": {
          Enums: {
            
          }
        }
} as const
